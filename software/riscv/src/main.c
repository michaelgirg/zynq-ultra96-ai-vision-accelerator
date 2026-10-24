#include <stdint.h>

#include "axi_dma_regs.h"
#include "job_mailbox.h"
#include "soc_address_map.h"
#include "vision_accel_regs.h"

#ifndef CONTROLLER_POLL_LIMIT
#define CONTROLLER_POLL_LIMIT 1000000u
#endif

// Supported low-32-bit DDR window; the host still owns allocation/cache care.
#define DMA_DDR_FIRST 0x00100000u
#define DMA_DDR_END   0x80000000u
static int controller_quarantined;
static const uint32_t mode_capabilities[4] = {1u, 2u, 4u, 8u};

typedef struct {
    uint32_t input_addr;
    uint32_t output_addr;
    uint32_t transfer_bytes;
    uint32_t mode;
    uint32_t threshold;
    uint32_t job_id;
} vision_job_t;

static uint32_t wait_for_dma_idle(uint32_t status_offset)
{
    for (uint32_t poll = 0; poll < CONTROLLER_POLL_LIMIT; ++poll) {
        uint32_t tx = mmio_read32(SOC_AXI_DMA_BASE, DMA_MM2S_DMASR);
        uint32_t rx = mmio_read32(SOC_AXI_DMA_BASE, DMA_S2MM_DMASR);
        if ((tx & DMA_DMASR_ERROR_MASK) != 0u) return MAILBOX_ERROR_DMA_MM2S;
        if ((rx & DMA_DMASR_ERROR_MASK) != 0u) return MAILBOX_ERROR_DMA_S2MM;
        uint32_t status = status_offset == DMA_MM2S_DMASR ? tx : rx;
        if ((status & DMA_DMASR_IDLE) != 0u) {
            return 0u;
        }
    }
    return MAILBOX_ERROR_TIMEOUT;
}

static void publish_failure(uint32_t error_code)
{
    mmio_write32(SOC_MAILBOX_BASE, MAILBOX_REG_ERROR_CODE, error_code);
    mmio_write32(SOC_MAILBOX_BASE, MAILBOX_REG_COMMAND, MAILBOX_CMD_FAIL);
}

static int valid_buffer(uint32_t address, uint32_t bytes)
{
    return (address & 3u) == 0u && address >= DMA_DDR_FIRST &&
           address < DMA_DDR_END && bytes <= DMA_DDR_END - address;
}

static int validate_job(const vision_job_t *job, uint32_t pixels, uint32_t capabilities)
{
    return pixels != 0u && pixels <= (DMA_DDR_END - DMA_DDR_FIRST) / 4u &&
           job->transfer_bytes == pixels * 4u &&
           valid_buffer(job->input_addr, job->transfer_bytes) &&
           valid_buffer(job->output_addr, job->transfer_bytes) &&
           (job->input_addr + job->transfer_bytes <= job->output_addr ||
            job->output_addr + job->transfer_bytes <= job->input_addr) &&
           job->mode <= VISION_MODE_VECTOR4 &&
           (capabilities & mode_capabilities[job->mode]) != 0u &&
           job->threshold <= 255u;
}

static int recover_datapath(void)
{
    // PG021: a soft reset of either channel resets the entire DMA engine.
    // Abort flushes accelerator FIFOs/line-buffer state, preserving coefficients.
    mmio_write32(SOC_AXI_DMA_BASE, DMA_MM2S_DMACR, DMA_DMACR_RESET);
    mmio_write32(SOC_VISION_ACCEL_BASE, VISION_REG_CTRL, VISION_CTRL_ABORT);
    for (uint32_t poll = 0; poll < CONTROLLER_POLL_LIMIT; ++poll) {
        if ((mmio_read32(SOC_AXI_DMA_BASE, DMA_MM2S_DMACR) & DMA_DMACR_RESET) == 0u) {
            uint32_t status = mmio_read32(SOC_VISION_ACCEL_BASE, VISION_REG_STATUS);
            if ((status & (VISION_STATUS_BUSY | VISION_STATUS_ARMED)) == 0u) {
                mmio_write32(SOC_VISION_ACCEL_BASE, VISION_REG_ERROR_STATUS, 0x7u);
                mmio_write32(SOC_VISION_ACCEL_BASE, VISION_REG_INT_STATUS, 0x7u);
                return 0;
            }
        }
    }
    controller_quarantined = 1;
    return -1;
}

static uint32_t execute_job(const vision_job_t *job)
{
    if (controller_quarantined) return MAILBOX_ERROR_RECOVERY;
    if (mmio_read32(SOC_VISION_ACCEL_BASE, VISION_REG_IP_ID) !=
        VISION_IP_ID_VALUE ||
        mmio_read32(SOC_VISION_ACCEL_BASE, VISION_REG_IP_VERSION) < VISION_IP_VERSION_RECOVERY) {
        return MAILBOX_ERROR_BAD_ID;
    }
    if (!validate_job(job,
            mmio_read32(SOC_VISION_ACCEL_BASE, VISION_REG_IMAGE_PIXELS),
            mmio_read32(SOC_VISION_ACCEL_BASE, VISION_REG_CAPABILITIES))) {
        return MAILBOX_ERROR_BAD_JOB;
    }

    mmio_write32(SOC_VISION_ACCEL_BASE, VISION_REG_ERROR_STATUS, 0x7u);
    mmio_write32(SOC_VISION_ACCEL_BASE, VISION_REG_INT_STATUS, 0x7u);
    mmio_write32(SOC_VISION_ACCEL_BASE, VISION_REG_MODE, job->mode);
    mmio_write32(SOC_VISION_ACCEL_BASE, VISION_REG_THRESHOLD, job->threshold);

    // Arm the receive side first so accelerator output can never be dropped.
    mmio_write32(SOC_AXI_DMA_BASE, DMA_S2MM_DMACR, DMA_DMACR_RUNSTOP);
    mmio_write32(SOC_AXI_DMA_BASE, DMA_S2MM_DA, job->output_addr);
    mmio_write32(SOC_AXI_DMA_BASE, DMA_S2MM_LENGTH, job->transfer_bytes);

    mmio_write32(SOC_AXI_DMA_BASE, DMA_MM2S_DMACR, DMA_DMACR_RUNSTOP);
    mmio_write32(SOC_AXI_DMA_BASE, DMA_MM2S_SA, job->input_addr);

    mmio_write32(SOC_VISION_ACCEL_BASE, VISION_REG_CTRL, VISION_CTRL_START);
    mmio_write32(SOC_AXI_DMA_BASE, DMA_MM2S_LENGTH, job->transfer_bytes);

    uint32_t mm2s_status = wait_for_dma_idle(DMA_MM2S_DMASR);
    if (mm2s_status != 0u) return mm2s_status;

    uint32_t s2mm_status = wait_for_dma_idle(DMA_S2MM_DMASR);
    if (s2mm_status != 0u) return s2mm_status;

    uint32_t accelerator_status =
        mmio_read32(SOC_VISION_ACCEL_BASE, VISION_REG_STATUS);
    uint32_t accelerator_errors =
        mmio_read32(SOC_VISION_ACCEL_BASE, VISION_REG_ERROR_STATUS);
    if ((accelerator_status & VISION_STATUS_PACKET_ERROR) != 0u ||
        accelerator_errors != 0u) {
        return MAILBOX_ERROR_ACCELERATOR;
    }

    return 0u;
}

int main(void)
{
    for (;;) {
        uint32_t status = mmio_read32(SOC_MAILBOX_BASE, MAILBOX_REG_STATUS);
        if ((status & MAILBOX_STATUS_PENDING) == 0u) {
            continue;
        }

        mmio_write32(SOC_MAILBOX_BASE, MAILBOX_REG_COMMAND, MAILBOX_CMD_CLAIM);

        vision_job_t job = {
            .input_addr = mmio_read32(SOC_MAILBOX_BASE, MAILBOX_REG_INPUT_ADDR),
            .output_addr = mmio_read32(SOC_MAILBOX_BASE, MAILBOX_REG_OUTPUT_ADDR),
            .transfer_bytes = mmio_read32(SOC_MAILBOX_BASE, MAILBOX_REG_TRANSFER_BYTES),
            .mode = mmio_read32(SOC_MAILBOX_BASE, MAILBOX_REG_MODE),
            .threshold = mmio_read32(SOC_MAILBOX_BASE, MAILBOX_REG_THRESHOLD),
            .job_id = mmio_read32(SOC_MAILBOX_BASE, MAILBOX_REG_JOB_ID),
        };

        uint32_t error = execute_job(&job);
        if (error != 0u) {
            if (error >= MAILBOX_ERROR_DMA_MM2S && error <= MAILBOX_ERROR_TIMEOUT &&
                recover_datapath() != 0) {
                error = MAILBOX_ERROR_RECOVERY;
            }
            publish_failure(error);
            continue;
        }

        mmio_write32(SOC_MAILBOX_BASE, MAILBOX_REG_RESULT, MAILBOX_RESULT_OK);
        mmio_write32(SOC_MAILBOX_BASE, MAILBOX_REG_COMMAND, MAILBOX_CMD_COMPLETE);
    }
}

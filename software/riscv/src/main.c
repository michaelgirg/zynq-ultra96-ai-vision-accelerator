#include <stdint.h>

#include "axi_dma_regs.h"
#include "job_mailbox.h"
#include "soc_address_map.h"
#include "vision_accel_regs.h"

#define CONTROLLER_POLL_LIMIT 1000000u

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
        uint32_t status = mmio_read32(SOC_AXI_DMA_BASE, status_offset);
        if ((status & DMA_DMASR_ERROR_MASK) != 0u) {
            return status;
        }
        if ((status & DMA_DMASR_IDLE) != 0u) {
            return status;
        }
    }
    return 0xFFFFFFFFu;
}

static void publish_failure(uint32_t error_code)
{
    mmio_write32(SOC_MAILBOX_BASE, MAILBOX_REG_ERROR_CODE, error_code);
    mmio_write32(SOC_MAILBOX_BASE, MAILBOX_REG_COMMAND, MAILBOX_CMD_FAIL);
}

static int validate_job(const vision_job_t *job)
{
    return job->input_addr != 0u &&
           job->output_addr != 0u &&
           job->transfer_bytes != 0u &&
           (job->transfer_bytes & 3u) == 0u &&
           job->mode <= VISION_MODE_VECTOR4 &&
           job->threshold <= 255u;
}

static uint32_t execute_job(const vision_job_t *job)
{
    if (!validate_job(job)) {
        return MAILBOX_ERROR_BAD_JOB;
    }

    if (mmio_read32(SOC_VISION_ACCEL_BASE, VISION_REG_IP_ID) !=
        VISION_IP_ID_VALUE) {
        return MAILBOX_ERROR_BAD_ID;
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
    if (mm2s_status == 0xFFFFFFFFu) {
        return MAILBOX_ERROR_TIMEOUT;
    }
    if ((mm2s_status & DMA_DMASR_ERROR_MASK) != 0u) {
        return MAILBOX_ERROR_DMA_MM2S;
    }

    uint32_t s2mm_status = wait_for_dma_idle(DMA_S2MM_DMASR);
    if (s2mm_status == 0xFFFFFFFFu) {
        return MAILBOX_ERROR_TIMEOUT;
    }
    if ((s2mm_status & DMA_DMASR_ERROR_MASK) != 0u) {
        return MAILBOX_ERROR_DMA_S2MM;
    }

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
            publish_failure(error);
            continue;
        }

        mmio_write32(SOC_MAILBOX_BASE, MAILBOX_REG_RESULT, MAILBOX_RESULT_OK);
        mmio_write32(SOC_MAILBOX_BASE, MAILBOX_REG_COMMAND, MAILBOX_CMD_COMPLETE);
    }
}

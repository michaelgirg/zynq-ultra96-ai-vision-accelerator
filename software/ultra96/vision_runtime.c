#include "vision_runtime.h"
#include "soc_address_map.h"
#include "vision_accel_regs.h"
#include "axi_dma_regs.h"
#include "job_mailbox.h"
#include <string.h>

static int rd(vision_device_t *d, uintptr_t addr, uint32_t *v)
{ return d->platform.read32(d->platform.context, addr, v) == 0 ? 0 : VISION_IO_ERROR; }
static int wr(vision_device_t *d, uintptr_t addr, uint32_t v)
{ return d->platform.write32(d->platform.context, addr, v) == 0 ? 0 : VISION_IO_ERROR; }
static uint64_t now(vision_device_t *d) { return d->platform.ticks(d->platform.context); }
static void barrier(vision_device_t *d) { d->platform.barrier(d->platform.context); }

static int valid_buffer(vision_dma_buffer_t b)
{
    return b.cpu != NULL && ((uintptr_t)b.cpu & 63u) == 0u &&
        (uintptr_t)b.cpu <= UINTPTR_MAX - VISION_FRAME_BYTES &&
        (b.physical & 63u) == 0u && b.capacity >= VISION_FRAME_BYTES &&
        b.physical >= 0x00100000u && b.physical <= 0x80000000u - VISION_FRAME_BYTES;
}

int vision_device_init(vision_device_t *d, const vision_platform_t *p,
    vision_dma_buffer_t input, vision_dma_buffer_t output,
    enum vision_control control, uint64_t timeout_ticks, uint32_t poll_limit)
{
    if (d == NULL || p == NULL) return VISION_INVALID;
    memset(d, 0, sizeof(*d));
    if (!p->read32 || !p->write32 || !p->clean || !p->invalidate || !p->barrier ||
        !p->ticks || !p->ticks_per_second || !p->backend_name ||
        !timeout_ticks || timeout_ticks >= (UINT64_MAX / 2) || !poll_limit ||
        !valid_buffer(input) || !valid_buffer(output) ||
        !(input.physical + VISION_FRAME_BYTES <= output.physical ||
          output.physical + VISION_FRAME_BYTES <= input.physical) ||
        !((uintptr_t)input.cpu + VISION_FRAME_BYTES <= (uintptr_t)output.cpu ||
          (uintptr_t)output.cpu + VISION_FRAME_BYTES <= (uintptr_t)input.cpu) ||
        (control != VISION_RV32_CONTROL && control != VISION_ARM_CONTROL)) return VISION_INVALID;
    d->platform = *p; d->input = input; d->output = output;
    d->control = control; d->timeout_ticks = timeout_ticks; d->poll_limit = poll_limit;
    return VISION_OK;
}

static int load_image(vision_device_t *d, uintptr_t base, const uint32_t *words, size_t count)
{
    uint32_t value;
    for (size_t i = 0; i < count; ++i) if (wr(d, base + i*4, words[i])) return VISION_IO_ERROR;
    barrier(d);
    for (size_t i = 0; i < count; ++i) {
        if (rd(d, base + i*4, &value)) return VISION_IO_ERROR;
        if (value != words[i]) return VISION_VERIFY_ERROR;
    }
    return VISION_OK;
}

int vision_device_boot(vision_device_t *d, const uint32_t *imem, size_t ni,
    const uint32_t *dmem, size_t nd, const vision_front_t *front)
{
    uint32_t value, version;
    int result;
    if (d == NULL || !d->platform.write32) return VISION_INVALID;
    d->ready = 0;
    if (wr(d, SOC_MAILBOX_BASE + MAILBOX_REG_BOOT_CONTROL, 0)) return VISION_IO_ERROR;
    barrier(d);
    if (d->quarantined) return VISION_NEEDS_RESET;
    if (!imem || ni == 0 || ni > 16384 || nd > 16384 || (nd && !dmem) || !front)
        return VISION_INVALID;
    for (int f = 0; f < 4; ++f) if (front->shift[f] > 31 || front->relu[f] > 1)
        return VISION_INVALID;
#define EXPECT(address, expected) do { if (rd(d, (address), &value)) return VISION_IO_ERROR; \
    if (value != (expected)) return VISION_ID_MISMATCH; } while (0)
    EXPECT(SOC_MAILBOX_BASE + MAILBOX_REG_ID, MAILBOX_ID_VALUE);
    EXPECT(SOC_MAILBOX_BASE + MAILBOX_REG_VERSION, MAILBOX_VERSION_VALUE);
    if (rd(d, SOC_MAILBOX_BASE + MAILBOX_REG_AXI_STATUS, &value)) return VISION_IO_ERROR;
    if (value & MAILBOX_AXI_QUARANTINED) { d->quarantined = 1; return VISION_NEEDS_RESET; }
    EXPECT(SOC_VISION_ACCEL_BASE + VISION_REG_IP_ID, VISION_IP_ID_VALUE);
    if (rd(d, SOC_VISION_ACCEL_BASE + VISION_REG_IP_VERSION, &value)) return VISION_IO_ERROR;
    if (value < VISION_IP_VERSION_RECOVERY) return VISION_ID_MISMATCH;
    EXPECT(SOC_VISION_ACCEL_BASE + VISION_REG_IMAGE_PIXELS, 784u);
    if (rd(d, SOC_VISION_ACCEL_BASE + VISION_REG_CAPABILITIES, &value)) return VISION_IO_ERROR;
    if ((value & 8u) == 0) return VISION_ID_MISMATCH;
    if (rd(d, SOC_MAILBOX_BASE + MAILBOX_REG_STATUS, &value)) return VISION_IO_ERROR;
    if (value != 0) return VISION_BUSY;
    if (rd(d, SOC_VISION_ACCEL_BASE + VISION_REG_STATUS, &value)) return VISION_IO_ERROR;
    if (value & (VISION_STATUS_BUSY | VISION_STATUS_ARMED)) return VISION_BUSY;
    for (int channel = 0; channel < 2; ++channel) {
        if (rd(d, SOC_AXI_DMA_BASE + (channel ? DMA_S2MM_DMASR : DMA_MM2S_DMASR), &value))
            return VISION_IO_ERROR;
        if (value & DMA_DMASR_ERROR_MASK) { d->quarantined = 1; return VISION_NEEDS_RESET; }
        if (!(value & (DMA_DMASR_IDLE | DMA_DMASR_HALTED))) return VISION_BUSY;
    }
    if ((result = load_image(d, SOC_HOST_IMEM_BASE, imem, ni)) != 0) return result;
    if ((result = load_image(d, SOC_HOST_DMEM_BASE, dmem, nd)) != 0) return result;
    if (rd(d, SOC_VISION_ACCEL_BASE + VISION_REG_VECTOR_CFG_VERSION, &version)) return VISION_IO_ERROR;
    for (int f = 0; f < 4; ++f) for (int entry = 0; entry < 11; ++entry) {
        uint32_t word = entry < 9 ? (uint32_t)(int32_t)front->weights[f][entry] :
            entry == 9 ? (uint32_t)front->bias[f] :
            ((uint32_t)front->relu[f] << 8) | front->shift[f];
        if (wr(d, SOC_VISION_ACCEL_BASE + 0x60u, (uint32_t)(f*16+entry)) ||
            wr(d, SOC_VISION_ACCEL_BASE + 0x64u, word)) return VISION_IO_ERROR;
        if (rd(d, SOC_VISION_ACCEL_BASE + 0x64u, &value)) return VISION_IO_ERROR;
        if (value != word) return VISION_VERIFY_ERROR;
    }
    if (wr(d, SOC_VISION_ACCEL_BASE + VISION_REG_VECTOR_CFG_COMMIT, 1)) return VISION_IO_ERROR;
    if (rd(d, SOC_VISION_ACCEL_BASE + VISION_REG_VECTOR_CFG_VERSION, &value)) return VISION_IO_ERROR;
    if (value != version + 1u) return VISION_VERIFY_ERROR;
#undef EXPECT
    barrier(d);
    if (d->control == VISION_RV32_CONTROL &&
        wr(d, SOC_MAILBOX_BASE + MAILBOX_REG_BOOT_CONTROL, 1)) return VISION_IO_ERROR;
    barrier(d);
    d->ready = 1;
    return VISION_OK;
}

static int mailbox_snapshot(vision_device_t *d, vision_diagnostics_t *s)
{
    uint32_t low = 0, high = 0;
    if (rd(d, SOC_MAILBOX_BASE + MAILBOX_REG_STATUS, &s->mailbox_status) ||
        rd(d, SOC_MAILBOX_BASE + MAILBOX_REG_AXI_STATUS, &s->axi_status)) return VISION_IO_ERROR;
#define FIELD(name, reg) (void)rd(d, SOC_MAILBOX_BASE + (reg), &s->name)
    FIELD(first_fault_kind, MAILBOX_REG_FIRST_FAULT_KIND);
    FIELD(first_fault_job, MAILBOX_REG_FIRST_FAULT_JOB);
    FIELD(first_fault_code, MAILBOX_REG_FIRST_FAULT_CODE);
    FIELD(first_fault_addr, MAILBOX_REG_FIRST_FAULT_ADDR);
    FIELD(first_fault_info, MAILBOX_REG_FIRST_FAULT_INFO);
    FIELD(first_fault_wait, MAILBOX_REG_FIRST_FAULT_WAIT);
    FIELD(axi_fault_addr, MAILBOX_REG_AXI_FAULT_ADDR);
    FIELD(axi_fault_info, MAILBOX_REG_AXI_FAULT_INFO);
    FIELD(axi_fault_wait, MAILBOX_REG_AXI_FAULT_WAIT);
#undef FIELD
    /* Captured timestamp pairs are stable in terminal/quarantined ownership.
     * A single host owns descriptors; never submit a new job during snapshot. */
#define TIME(name, reg) do { low = high = 0; \
    (void)rd(d, SOC_MAILBOX_BASE + (reg), &low); \
    (void)rd(d, SOC_MAILBOX_BASE + (reg) + 4u, &high); \
    s->name = ((uint64_t)high << 32) | low; } while (0)
    TIME(submit_cycles, MAILBOX_REG_SUBMIT_LO);
    TIME(claim_cycles, MAILBOX_REG_CLAIM_LO);
    TIME(end_cycles, MAILBOX_REG_END_LO);
    TIME(job_cycles, MAILBOX_REG_JOB_CYCLES_LO);
#undef TIME
    return VISION_OK;
}

static void snapshot(vision_device_t *d, vision_diagnostics_t *s)
{
    if (mailbox_snapshot(d, s) != VISION_OK) { d->quarantined = 1; return; }
    // A timed-out target may still be wedged. Do not touch DMA/accelerator
    // registers, ACK ownership, reset only the CPU, or reuse DMA buffers.
    if (s->axi_status & MAILBOX_AXI_QUARANTINED) { d->quarantined = 1; return; }
    (void)rd(d, SOC_AXI_DMA_BASE + DMA_MM2S_DMASR, &s->mm2s_status);
    (void)rd(d, SOC_AXI_DMA_BASE + DMA_S2MM_DMASR, &s->s2mm_status);
    (void)rd(d, SOC_VISION_ACCEL_BASE + VISION_REG_STATUS, &s->accelerator_status);
    (void)rd(d, SOC_VISION_ACCEL_BASE + VISION_REG_ERROR_STATUS, &s->accelerator_errors);
    (void)rd(d, SOC_VISION_ACCEL_BASE + VISION_REG_PROCESSING_CYCLES, &s->accelerator_cycles);
}

static int arm_recover(vision_device_t *d)
{
    uint32_t dma, accel;
    uint64_t start = now(d);
    if (wr(d, SOC_AXI_DMA_BASE + DMA_MM2S_DMACR, DMA_DMACR_RESET) ||
        wr(d, SOC_VISION_ACCEL_BASE + VISION_REG_CTRL, VISION_CTRL_ABORT)) return VISION_IO_ERROR;
    for (uint32_t poll = 0; poll < d->poll_limit; ++poll) {
        if (rd(d, SOC_AXI_DMA_BASE + DMA_MM2S_DMACR, &dma) ||
            rd(d, SOC_VISION_ACCEL_BASE + VISION_REG_STATUS, &accel)) return VISION_IO_ERROR;
        if (!(dma & DMA_DMACR_RESET) && !(accel & 9u)) return VISION_OK;
        if (now(d) - start >= d->timeout_ticks) break;
    }
    return VISION_NEEDS_RESET;
}

static int dispatch(vision_device_t *d, vision_diagnostics_t *s)
{
    uint32_t status, result, error, causes = 0;
    uint64_t start = now(d);
#define WRITE(base, offset, v) do { if (wr(d, (base)+(offset), (v))) return VISION_IO_ERROR; } while (0)
    if (d->control == VISION_RV32_CONTROL) {
        if (rd(d, SOC_MAILBOX_BASE + MAILBOX_REG_AXI_STATUS, &status)) return VISION_IO_ERROR;
        if (status & MAILBOX_AXI_QUARANTINED) { d->quarantined = 1; return VISION_NEEDS_RESET; }
        if (rd(d, SOC_MAILBOX_BASE + MAILBOX_REG_STATUS, &status)) return VISION_IO_ERROR;
        if (status != 0) return VISION_BUSY;
        WRITE(SOC_MAILBOX_BASE, MAILBOX_REG_IRQ_ENABLE, 0);
        if (d->use_irq) {
            if (d->platform.irq_prepare(d->platform.context)) return VISION_IO_ERROR;
            WRITE(SOC_MAILBOX_BASE, MAILBOX_REG_IRQ_STATUS, 7);
            if (rd(d, SOC_MAILBOX_BASE + MAILBOX_REG_AXI_STATUS, &status)) return VISION_IO_ERROR;
            if (status & MAILBOX_AXI_QUARANTINED) { d->quarantined = 1; return VISION_NEEDS_RESET; }
            WRITE(SOC_MAILBOX_BASE, MAILBOX_REG_IRQ_ENABLE, 7);
        }
        WRITE(SOC_MAILBOX_BASE, MAILBOX_REG_INPUT_ADDR, d->input.physical);
        WRITE(SOC_MAILBOX_BASE, MAILBOX_REG_OUTPUT_ADDR, d->output.physical);
        WRITE(SOC_MAILBOX_BASE, MAILBOX_REG_TRANSFER_BYTES, VISION_FRAME_BYTES);
        WRITE(SOC_MAILBOX_BASE, MAILBOX_REG_MODE, 3);
        WRITE(SOC_MAILBOX_BASE, MAILBOX_REG_THRESHOLD, 128);
        WRITE(SOC_MAILBOX_BASE, MAILBOX_REG_JOB_ID, s->job_id);
        barrier(d);
        WRITE(SOC_MAILBOX_BASE, MAILBOX_REG_COMMAND, MAILBOX_CMD_SUBMIT);
    } else {
        WRITE(SOC_VISION_ACCEL_BASE, VISION_REG_ERROR_STATUS, 7);
        WRITE(SOC_VISION_ACCEL_BASE, VISION_REG_INT_STATUS, 7);
        WRITE(SOC_VISION_ACCEL_BASE, VISION_REG_MODE, 3);
        WRITE(SOC_AXI_DMA_BASE, DMA_S2MM_DMACR, DMA_DMACR_RUNSTOP);
        WRITE(SOC_AXI_DMA_BASE, DMA_S2MM_DA, d->output.physical);
        WRITE(SOC_AXI_DMA_BASE, DMA_S2MM_LENGTH, VISION_FRAME_BYTES);
        WRITE(SOC_AXI_DMA_BASE, DMA_MM2S_DMACR, DMA_DMACR_RUNSTOP);
        WRITE(SOC_AXI_DMA_BASE, DMA_MM2S_SA, d->input.physical);
        WRITE(SOC_VISION_ACCEL_BASE, VISION_REG_CTRL, VISION_CTRL_START);
        barrier(d);
        WRITE(SOC_AXI_DMA_BASE, DMA_MM2S_LENGTH, VISION_FRAME_BYTES);
    }
    s->stage = VISION_STAGE_WAIT;
    if (d->use_irq) {
        int waited = d->platform.irq_wait(d->platform.context, &causes,
            d->timeout_ticks, d->poll_limit);
        WRITE(SOC_MAILBOX_BASE, MAILBOX_REG_IRQ_ENABLE, 0);
        if (waited != VISION_OK) return waited;
        if (causes & 4u) { d->quarantined = 1; return VISION_NEEDS_RESET; }
        if (causes != 1u && causes != 2u) return VISION_VERIFY_ERROR;
    }
    for (s->polls = 0; s->polls < d->poll_limit; ++s->polls) {
        if (d->control == VISION_RV32_CONTROL) {
            if (rd(d, SOC_MAILBOX_BASE + MAILBOX_REG_AXI_STATUS, &status)) return VISION_IO_ERROR;
            if (status & MAILBOX_AXI_QUARANTINED) {
                d->quarantined = 1;
                (void)mailbox_snapshot(d, s);
                return VISION_NEEDS_RESET;
            }
            if (rd(d, SOC_MAILBOX_BASE + MAILBOX_REG_STATUS, &status)) return VISION_IO_ERROR;
            if (d->use_irq && status != (causes == 1u ? MAILBOX_STATUS_DONE : MAILBOX_STATUS_ERROR))
                return VISION_VERIFY_ERROR;
            if (status & (MAILBOX_STATUS_DONE | MAILBOX_STATUS_ERROR)) {
                if (rd(d, SOC_MAILBOX_BASE + MAILBOX_REG_JOB_ID, &result)) return VISION_IO_ERROR;
                if (result != s->job_id) return VISION_VERIFY_ERROR;
                if (rd(d, SOC_MAILBOX_BASE + MAILBOX_REG_ERROR_CODE, &error) ||
                    rd(d, SOC_MAILBOX_BASE + MAILBOX_REG_RESULT, &result)) return VISION_IO_ERROR;
                s->firmware_error = error;
                snapshot(d, s); /* Capture evidence before ACK clears terminal registers. */
                if (d->quarantined) return VISION_NEEDS_RESET;
                if (status != MAILBOX_STATUS_DONE || error || result != MAILBOX_RESULT_OK) {
                    WRITE(SOC_MAILBOX_BASE, MAILBOX_REG_COMMAND, MAILBOX_CMD_ACK);
                    if (error == MAILBOX_ERROR_RECOVERY) d->quarantined = 1;
                    return VISION_JOB_FAILED;
                }
                if (!(s->mm2s_status & DMA_DMASR_IDLE) || !(s->s2mm_status & DMA_DMASR_IDLE) ||
                    !(s->accelerator_status & VISION_STATUS_DONE) || (s->accelerator_status & 9u) ||
                    s->accelerator_errors) return VISION_VERIFY_ERROR;
                WRITE(SOC_MAILBOX_BASE, MAILBOX_REG_COMMAND, MAILBOX_CMD_ACK);
                return VISION_OK;
            }
        } else {
            if (rd(d, SOC_AXI_DMA_BASE + DMA_MM2S_DMASR, &s->mm2s_status) ||
                rd(d, SOC_AXI_DMA_BASE + DMA_S2MM_DMASR, &s->s2mm_status)) return VISION_IO_ERROR;
            if (s->mm2s_status & DMA_DMASR_ERROR_MASK) { s->firmware_error = 3; return VISION_JOB_FAILED; }
            if (s->s2mm_status & DMA_DMASR_ERROR_MASK) { s->firmware_error = 4; return VISION_JOB_FAILED; }
            if ((s->mm2s_status & DMA_DMASR_IDLE) && (s->s2mm_status & DMA_DMASR_IDLE)) {
                snapshot(d, s);
                if (s->accelerator_errors || (s->accelerator_status & VISION_STATUS_PACKET_ERROR)) {
                    s->firmware_error = 5; return VISION_JOB_FAILED;
                }
                if ((s->accelerator_status & VISION_STATUS_DONE) && !(s->accelerator_status & 9u))
                    return VISION_OK;
            }
        }
        if (now(d) - start >= d->timeout_ticks) return VISION_DEADLINE;
    }
#undef WRITE
    return VISION_DEADLINE; /* Poll cap also bounds a stopped/broken timer. */
}

int vision_run_image(vision_device_t *d, const uint8_t image[784],
    const vector_classifier_model_t *model, vision_run_t *run)
{
    uint64_t start, mark, next;
    int result;
    uint32_t axi_status;
    if (!d || !image || !model || !model->fc1_weights || !model->fc1_bias ||
        !model->fc2_weights || !model->fc2_bias || !run) return VISION_INVALID;
    memset(run, 0, sizeof(*run)); run->prediction = -1;
    if (d->quarantined) return run->diagnostics.result = VISION_NEEDS_RESET;
    if (!d->ready) return run->diagnostics.result = VISION_INVALID;
    /* Faults may arrive between jobs. Discover quarantine before changing or
     * cleaning any DMA buffer, not only later inside descriptor dispatch. */
    if (rd(d, SOC_MAILBOX_BASE + MAILBOX_REG_AXI_STATUS, &axi_status)) {
        d->quarantined = 1;
        return run->diagnostics.result = VISION_IO_ERROR;
    }
    if (axi_status & MAILBOX_AXI_QUARANTINED) {
        d->quarantined = 1;
        (void)mailbox_snapshot(d, &run->diagnostics);
        return run->diagnostics.result = VISION_NEEDS_RESET;
    }
    start = mark = now(d);
    run->diagnostics.job_id = ++d->next_job;
    run->diagnostics.stage = VISION_STAGE_PREPARE;
    for (int i = 0; i < 784; ++i) d->input.cpu[i] = image[i];
    next = now(d); run->prepare = next-mark; mark = next;
    run->diagnostics.stage = VISION_STAGE_CACHE;
    if (d->platform.clean(d->platform.context, d->input.cpu, VISION_FRAME_BYTES) ||
        d->platform.clean(d->platform.context, d->output.cpu, VISION_FRAME_BYTES)) {
        result = VISION_IO_ERROR; goto failed;
    }
    barrier(d);
    next = now(d); run->cache_clean = next-mark; mark = next;
    run->diagnostics.stage = VISION_STAGE_SUBMIT;
    result = dispatch(d, &run->diagnostics);
    next = now(d); run->submit_wait = next-mark; mark = next;
    if (result != VISION_OK) goto failed;
    run->diagnostics.stage = VISION_STAGE_CACHE;
    barrier(d);
    if (d->platform.invalidate(d->platform.context, d->output.cpu, VISION_FRAME_BYTES)) {
        result = VISION_IO_ERROR; goto failed;
    }
    barrier(d);
    next = now(d); run->cache_invalidate = next-mark; mark = next;
    run->diagnostics.stage = VISION_STAGE_CLASSIFY;
    run->prediction = vector_classifier_predict(d->output.cpu, model, run->logits);
    run->classifier = now(d)-mark;
    run->total = now(d)-start;
    run->diagnostics.result = VISION_OK;
    run->diagnostics.stage = VISION_STAGE_IDLE;
    return VISION_OK;
failed:
    if (d->use_irq) (void)wr(d, SOC_MAILBOX_BASE + MAILBOX_REG_IRQ_ENABLE, 0);
    snapshot(d, &run->diagnostics);
    if (run->diagnostics.axi_status & MAILBOX_AXI_QUARANTINED) result = VISION_NEEDS_RESET;
    run->diagnostics.result = result;
    if (!d->quarantined && d->control == VISION_ARM_CONTROL &&
        (result == VISION_JOB_FAILED || result == VISION_DEADLINE)) {
        run->diagnostics.recovery_result = arm_recover(d);
        if (run->diagnostics.recovery_result != VISION_OK) d->quarantined = 1;
    } else if (result != VISION_JOB_FAILED && result != VISION_BUSY) d->quarantined = 1;
    run->total = now(d)-start;
    return result;
}

int vision_device_set_irq(vision_device_t *d, int enable)
{
    uint32_t status;
    if (!d || !d->ready || d->quarantined || d->control != VISION_RV32_CONTROL ||
        (enable && (!d->platform.irq_prepare || !d->platform.irq_wait))) return VISION_INVALID;
    if (rd(d, SOC_MAILBOX_BASE + MAILBOX_REG_STATUS, &status)) return VISION_IO_ERROR;
    if (status) return VISION_BUSY;
    if (wr(d, SOC_MAILBOX_BASE + MAILBOX_REG_IRQ_ENABLE, 0)) return VISION_IO_ERROR;
    d->use_irq = !!enable;
    return VISION_OK;
}

const char *vision_stage_name(enum vision_stage stage)
{
    static const char *const names[] = {"idle", "discovery", "boot", "model", "prepare",
        "cache", "submit", "wait", "classify", "recovery"};
    return (unsigned)stage < sizeof(names)/sizeof(names[0]) ? names[stage] : "unknown";
}

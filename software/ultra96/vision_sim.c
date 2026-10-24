#ifndef _WIN32
#define _POSIX_C_SOURCE 200809L
#endif
#include "vision_sim.h"
#include "soc_address_map.h"
#include "vision_accel_regs.h"
#include "axi_dma_regs.h"
#include "job_mailbox.h"
#include <string.h>
#ifdef _WIN32
#include <windows.h>
#else
#include <time.h>
#endif

static uint64_t ticks(void *context)
{
    vision_sim_t *s = context;
    if (s->clock_stopped) return 0;
#ifdef _WIN32
    LARGE_INTEGER t;
    QueryPerformanceCounter(&t);
    return (uint64_t)t.QuadPart;
#else
    struct timespec t;
    (void)clock_gettime(CLOCK_MONOTONIC, &t);
    return (uint64_t)t.tv_sec*1000000000u + (uint64_t)t.tv_nsec;
#endif
}

static void complete(vision_sim_t *s)
{
    uint8_t pixels[784];
    uint32_t error = 0;
    if (!s->active || s->fault == SIM_TIMEOUT || s->fault == SIM_STUCK_RESET) return;
    if (--s->countdown > 0) return;
    s->active = 0;
    s->tx_status = s->rx_status = 2;
    if (s->fault == SIM_MM2S) { error = 3; s->tx_status = 0x10; }
    if (s->fault == SIM_S2MM) { error = 4; s->rx_status = 0x10; }
    if (s->fault == SIM_PACKET) { error = 5; s->accel_error = 1; s->accel_status = 6; }
    if (!error) {
        for (int i = 0; i < 784; ++i) pixels[i] = (uint8_t)s->device_input[i];
        if (s->replay) memcpy(s->device_output, s->replay, sizeof(s->device_output));
        else (void)vector_front_reference(pixels, &s->front, s->device_output);
        s->tx_status = s->rx_status = 2;
        s->accel_status = 2;
    }
    if (s->resetn) {
        /* Functional firmware/mailbox model, NOT RV32 execution. RTL tests
         * separately execute the actual compiled controller. */
        s->mailbox[1] = error ? 8u : 4u;
        s->mailbox[8] = error ? 0u : 0x600du;
        s->mailbox[9] = error;
        if (error) {
            s->tx_status = s->rx_status = 2;
            s->accel_status = s->accel_error = 0;
        }
        if (s->fault == SIM_WRONG_JOB) ++s->mailbox[7];
    }
}

static int launch(vision_sim_t *s)
{
    if (!s->input_clean || !s->output_clean || s->barriers <= s->last_clean_barrier) return -1;
    if (s->source != 0x10000000u || s->destination != 0x10001000u ||
        s->tx_bytes != 3136 || s->rx_bytes != 3136 || s->mode != 3) return -1;
    s->input_clean = s->output_clean = 0;
    s->active = 1; s->countdown = 3; s->tx_status = s->rx_status = 0;
    s->accel_status = 9; s->accel_error = 0; ++s->launches;
    return 0;
}

static int read32(void *context, uintptr_t address, uint32_t *value)
{
    vision_sim_t *s = context;
    if (s->fault == SIM_IO_ERROR) return -1;
    uint32_t base = (uint32_t)address & 0xffff0000u;
    uint32_t offset = (uint32_t)address & 0xffffu;
    if (offset & 3u) return -1;
    if (base == SOC_HOST_IMEM_BASE || base == SOC_HOST_DMEM_BASE) {
        *value = base == SOC_HOST_IMEM_BASE ? s->imem[offset/4] : s->dmem[offset/4];
        if (s->fault == SIM_BAD_READBACK) *value ^= 1;
    } else if (base == SOC_MAILBOX_BASE && offset < 48) {
        if (offset == 4) complete(s);
        *value = s->mailbox[offset/4];
        if (offset == 0x28) *value = MAILBOX_ID_VALUE;
        if (offset == 0x2c) *value = (uint32_t)s->resetn;
    } else if (base == SOC_VISION_ACCEL_BASE) {
        switch (offset) {
            case 0x04: *value = s->accel_status; break;
            case 0x0c: *value = 784; break;
            case 0x14: *value = 0; break; /* Never fabricate hardware cycle measurements. */
            case 0x64: *value = s->shadow[s->cfg_index]; break;
            case 0x6c: *value = s->cfg_version; break;
            case 0x70: *value = VISION_IP_ID_VALUE ^ (uint32_t)(s->fault == SIM_BAD_ID); break;
            case 0x74: *value = s->fault == SIM_OLD_VERSION ? 0x20000u : VISION_IP_VERSION_RECOVERY; break;
            case 0x78: *value = 0xf044fu; break;
            case 0x8c: *value = s->accel_error; break;
            default: *value = 0; break;
        }
    } else if (base == SOC_AXI_DMA_BASE) {
        if (offset == DMA_MM2S_DMASR || offset == DMA_S2MM_DMASR) complete(s);
        switch (offset) {
            case DMA_MM2S_DMACR: *value = s->mm2s_ctrl; break;
            case DMA_MM2S_DMASR: *value = s->tx_status; break;
            case DMA_S2MM_DMASR: *value = s->rx_status; break;
            default: *value = 0; break;
        }
    } else return -1;
    return 0;
}

static int write32(void *context, uintptr_t address, uint32_t value)
{
    vision_sim_t *s = context;
    if (s->fault == SIM_IO_ERROR) return -1;
    uint32_t base = (uint32_t)address & 0xffff0000u;
    uint32_t offset = (uint32_t)address & 0xffffu;
    if (offset & 3u) return -1;
    if (base == SOC_HOST_IMEM_BASE || base == SOC_HOST_DMEM_BASE) {
        if (s->resetn) return -1;
        if (base == SOC_HOST_IMEM_BASE) s->imem[offset/4] = value;
        else s->dmem[offset/4] = value;
    } else if (base == SOC_MAILBOX_BASE && offset < 48) {
        if (offset == 0x2c) s->resetn = (int)(value & 1u);
        else if (offset == 0) {
            if (value == MAILBOX_CMD_SUBMIT) {
                if (!s->resetn || s->mailbox[1]) return -1;
                s->mailbox[1] = 2;
                s->source = s->mailbox[2]; s->destination = s->mailbox[3];
                s->tx_bytes = s->rx_bytes = s->mailbox[4]; s->mode = s->mailbox[5];
                return launch(s);
            }
            if (value == MAILBOX_CMD_ACK) {
                if (!(s->mailbox[1] & 12u)) return -1;
                s->mailbox[1] = s->mailbox[8] = s->mailbox[9] = 0;
            }
        } else s->mailbox[offset/4] = value;
    } else if (base == SOC_VISION_ACCEL_BASE) {
        switch (offset) {
            case 0x00:
                if (value & VISION_CTRL_ABORT) { s->active = 0; s->accel_status = 0; }
                else if (value & VISION_CTRL_START) s->accel_status = 9;
                break;
            case 0x2c: s->mode = value; break;
            case 0x60: if (value >= 64) return -1; s->cfg_index = value; break;
            case 0x64: s->shadow[s->cfg_index] = value; break;
            case 0x68:
                ++s->cfg_version;
                for (int f = 0; f < 4; ++f) {
                    for (int t = 0; t < 9; ++t) s->front.weights[f][t] = (int8_t)s->shadow[f*16+t];
                    s->front.bias[f] = (int32_t)s->shadow[f*16+9];
                    s->front.shift[f] = (uint8_t)(s->shadow[f*16+10] & 31u);
                    s->front.relu[f] = (uint8_t)((s->shadow[f*16+10] >> 8) & 1u);
                }
                break;
            case 0x8c: s->accel_error &= ~value; break;
            default: break;
        }
    } else if (base == SOC_AXI_DMA_BASE) {
        switch (offset) {
            case DMA_MM2S_DMACR:
                if (value & DMA_DMACR_RESET) {
                    ++s->resets; s->active = 0;
                    s->mm2s_ctrl = s->fault == SIM_STUCK_RESET ? 4u : 0u;
                    s->s2mm_ctrl = 0; s->tx_status = s->rx_status = 2;
                } else s->mm2s_ctrl = value;
                break;
            case DMA_S2MM_DMACR: s->s2mm_ctrl = value; break;
            case DMA_MM2S_SA: s->source = value; break;
            case DMA_S2MM_DA: s->destination = value; break;
            case DMA_S2MM_LENGTH:
                if (!s->s2mm_ctrl) return -1;
                s->rx_bytes = value; break;
            case DMA_MM2S_LENGTH:
                if (!s->s2mm_ctrl || !s->mm2s_ctrl) return -1;
                s->tx_bytes = value; return launch(s);
            default: break;
        }
    } else return -1;
    return 0;
}

static int clean(void *context, void *address, size_t count)
{
    vision_sim_t *s = context;
    if (s->fault == SIM_CACHE_ERROR || count != VISION_FRAME_BYTES) return -1;
    if (address == s->input) {
        memcpy(s->device_input, s->input, count); s->input_clean = 1;
    } else if (address == s->output) {
        memcpy(s->device_output, s->output, count); s->output_clean = 1;
    } else return -1;
    s->last_clean_barrier = s->barriers;
    return 0;
}
static int invalidate(void *context, void *address, size_t count)
{
    vision_sim_t *s = context;
    if (address != s->output || count != VISION_FRAME_BYTES || s->active) return -1;
    memcpy(s->output, s->device_output, count); ++s->invalidates;
    return 0;
}
static void barrier_cb(void *context) { ++((vision_sim_t *)context)->barriers; }

void vision_sim_init(vision_sim_t *s)
{
    memset(s, 0, sizeof(*s)); s->tx_status = s->rx_status = 2;
}
vision_platform_t vision_sim_platform(vision_sim_t *s)
{
    uint64_t frequency;
#ifdef _WIN32
    LARGE_INTEGER f;
    QueryPerformanceFrequency(&f); frequency = (uint64_t)f.QuadPart;
#else
    frequency = 1000000000u;
#endif
    vision_platform_t p = {s, read32, write32, clean, invalidate, barrier_cb, ticks,
        frequency, "native-functional-model", 0};
    return p;
}
vision_dma_buffer_t vision_sim_input(vision_sim_t *s)
{ vision_dma_buffer_t b = {s->input, 0x10000000u, sizeof(s->input)}; return b; }
vision_dma_buffer_t vision_sim_output(vision_sim_t *s)
{ vision_dma_buffer_t b = {s->output, 0x10001000u, sizeof(s->output)}; return b; }

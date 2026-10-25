#pragma once
#include "vision_runtime.h"

#ifdef _MSC_VER
#define VISION_ALIGN64 __declspec(align(64))
#else
#define VISION_ALIGN64 __attribute__((aligned(64)))
#endif

enum vision_sim_fault { SIM_NONE, SIM_BAD_ID, SIM_OLD_VERSION, SIM_BAD_READBACK,
    SIM_MM2S, SIM_S2MM, SIM_PACKET, SIM_TIMEOUT, SIM_STUCK_RESET,
    SIM_CACHE_ERROR, SIM_IO_ERROR, SIM_WRONG_JOB, SIM_BUS_TIMEOUT,
    SIM_IRQ_LOST, SIM_IRQ_SPURIOUS, SIM_IRQ_CONFLICT };

typedef struct {
    VISION_ALIGN64 uint32_t input[784];
    VISION_ALIGN64 uint32_t output[784];
    uint32_t device_input[784], device_output[784];
    uint32_t imem[16384], dmem[16384], mailbox[40];
    uint32_t shadow[64], cfg_index, cfg_version;
    vision_front_t front;
    uint32_t mm2s_ctrl, s2mm_ctrl, source, destination, tx_bytes, rx_bytes;
    uint32_t tx_status, rx_status, accel_status, accel_error, mode;
    int active, countdown, input_clean, output_clean, barriers, launches, invalidates;
    int resetn, resets, clock_stopped, last_clean_barrier;
    int unsafe_fault_reads;
    int irq_waits, irq_deliveries;
    enum vision_sim_fault fault;
    const uint32_t *replay; /* Optional real RTL-captured frame; never timing evidence. */
} vision_sim_t;

void vision_sim_init(vision_sim_t *);
vision_platform_t vision_sim_platform(vision_sim_t *);
vision_dma_buffer_t vision_sim_input(vision_sim_t *);
vision_dma_buffer_t vision_sim_output(vision_sim_t *);

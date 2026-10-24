#pragma once
#include <stddef.h>
#include <stdint.h>
#include "vector_classifier.h"
#include "vector_front_reference.h"

#define VISION_FRAME_BYTES 3136u
#define VISION_CACHE_ALIGNMENT 64u

typedef struct {
    void *context;
    int (*read32)(void *, uintptr_t, uint32_t *);
    int (*write32)(void *, uintptr_t, uint32_t);
    int (*clean)(void *, void *, size_t);
    int (*invalidate)(void *, void *, size_t);
    void (*barrier)(void *);
    uint64_t (*ticks)(void *);
    uint64_t ticks_per_second;
    const char *backend_name;
    int physical_hardware;
} vision_platform_t;

typedef struct {
    uint32_t *cpu;
    uint32_t physical;
    size_t capacity;
} vision_dma_buffer_t;

enum vision_control { VISION_RV32_CONTROL, VISION_ARM_CONTROL };
enum vision_stage { VISION_STAGE_IDLE, VISION_STAGE_DISCOVERY, VISION_STAGE_BOOT,
    VISION_STAGE_MODEL, VISION_STAGE_PREPARE, VISION_STAGE_CACHE,
    VISION_STAGE_SUBMIT, VISION_STAGE_WAIT, VISION_STAGE_CLASSIFY, VISION_STAGE_RECOVERY };
enum vision_result { VISION_OK = 0, VISION_INVALID = -1, VISION_IO_ERROR = -2,
    VISION_ID_MISMATCH = -3, VISION_VERIFY_ERROR = -4, VISION_BUSY = -5,
    VISION_DEADLINE = -6, VISION_JOB_FAILED = -7, VISION_NEEDS_RESET = -8 };

typedef struct {
    enum vision_stage stage;
    uint32_t job_id, mailbox_status, firmware_error, mm2s_status, s2mm_status;
    uint32_t accelerator_status, accelerator_errors, accelerator_cycles;
    int result, recovery_result;
    uint32_t polls;
} vision_diagnostics_t;

typedef struct {
    uint64_t prepare, cache_clean, submit_wait, cache_invalidate, classifier, total;
    int prediction;
    float logits[10];
    vision_diagnostics_t diagnostics;
} vision_run_t;

typedef struct {
    vision_platform_t platform;
    vision_dma_buffer_t input, output;
    uint64_t timeout_ticks;
    uint32_t poll_limit, next_job;
    enum vision_control control;
    int ready, quarantined;
} vision_device_t;

int vision_device_init(vision_device_t *, const vision_platform_t *,
    vision_dma_buffer_t input, vision_dma_buffer_t output,
    enum vision_control, uint64_t timeout_ticks, uint32_t poll_limit);
int vision_device_boot(vision_device_t *, const uint32_t *imem, size_t imem_words,
    const uint32_t *dmem, size_t dmem_words, const vision_front_t *);
int vision_run_image(vision_device_t *, const uint8_t image[784],
    const vector_classifier_model_t *, vision_run_t *);
const char *vision_stage_name(enum vision_stage);

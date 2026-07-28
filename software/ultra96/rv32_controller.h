#pragma once

#include <stddef.h>
#include <stdint.h>

#define RV32_MAILBOX_BASE_DEFAULT   0xA0020000u
#define RV32_HOST_IMEM_BASE_DEFAULT 0xA0030000u
#define RV32_HOST_DMEM_BASE_DEFAULT 0xA0040000u

typedef struct {
    uint32_t input_addr;
    uint32_t output_addr;
    uint32_t transfer_bytes;
    uint32_t mode;
    uint32_t threshold;
    uint32_t job_id;
} rv32_vision_job_t;

void rv32_load_memory_words(uintptr_t portal_base, const uint32_t *words, size_t word_count);
int rv32_verify_memory_words(uintptr_t portal_base, const uint32_t *words, size_t word_count);
void rv32_release_from_reset(uintptr_t mailbox_base);
int rv32_submit_job(uintptr_t mailbox_base, const rv32_vision_job_t *job);
int rv32_wait_for_job(
    uintptr_t mailbox_base,
    uint32_t poll_limit,
    uint32_t *result,
    uint32_t *error_code
);

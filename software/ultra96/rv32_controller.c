#include "rv32_controller.h"

#define MB_COMMAND        0x00u
#define MB_STATUS         0x04u
#define MB_INPUT_ADDR     0x08u
#define MB_OUTPUT_ADDR    0x0Cu
#define MB_TRANSFER_BYTES 0x10u
#define MB_MODE           0x14u
#define MB_THRESHOLD      0x18u
#define MB_JOB_ID         0x1Cu
#define MB_RESULT         0x20u
#define MB_ERROR_CODE     0x24u
#define MB_BOOT_CONTROL   0x2Cu

#define MB_CMD_SUBMIT 0x1u
#define MB_CMD_ACK    0x10u
#define MB_PENDING    0x1u
#define MB_BUSY       0x2u
#define MB_DONE       0x4u
#define MB_ERROR      0x8u

static void write32(uintptr_t base, uint32_t offset, uint32_t value)
{
    *(volatile uint32_t *)(base + offset) = value;
}

static uint32_t read32(uintptr_t base, uint32_t offset)
{
    return *(volatile uint32_t *)(base + offset);
}

void rv32_load_memory_words(uintptr_t portal_base, const uint32_t *words, size_t word_count)
{
    volatile uint32_t *portal = (volatile uint32_t *)portal_base;
    for (size_t index = 0; index < word_count; ++index) {
        portal[index] = words[index];
    }
}

int rv32_verify_memory_words(uintptr_t portal_base, const uint32_t *words, size_t word_count)
{
    const volatile uint32_t *portal = (const volatile uint32_t *)portal_base;
    for (size_t index = 0; index < word_count; ++index) {
        if (portal[index] != words[index]) {
            return -1;
        }
    }
    return 0;
}

void rv32_release_from_reset(uintptr_t mailbox_base)
{
    write32(mailbox_base, MB_BOOT_CONTROL, 1u);
}

void rv32_hold_in_reset(uintptr_t mailbox_base)
{
    write32(mailbox_base, MB_BOOT_CONTROL, 0u);
}

int rv32_boot_controller(
    uintptr_t mailbox_base,
    uintptr_t imem_portal_base,
    uintptr_t dmem_portal_base,
    const uint32_t *imem_words,
    size_t imem_word_count,
    const uint32_t *dmem_words,
    size_t dmem_word_count
)
{
    if (imem_word_count > RV32_LOCAL_MEMORY_WORDS ||
        dmem_word_count > RV32_LOCAL_MEMORY_WORDS ||
        (imem_word_count != 0u && imem_words == NULL) ||
        (dmem_word_count != 0u && dmem_words == NULL)) {
        return RV32_BOOT_BAD_IMAGE;
    }

    rv32_hold_in_reset(mailbox_base);
    rv32_load_memory_words(imem_portal_base, imem_words, imem_word_count);
    rv32_load_memory_words(dmem_portal_base, dmem_words, dmem_word_count);

    if (rv32_verify_memory_words(
            imem_portal_base, imem_words, imem_word_count) != 0) {
        return RV32_BOOT_IMEM_VERIFY;
    }
    if (rv32_verify_memory_words(
            dmem_portal_base, dmem_words, dmem_word_count) != 0) {
        return RV32_BOOT_DMEM_VERIFY;
    }

    rv32_release_from_reset(mailbox_base);
    return RV32_BOOT_OK;
}

int rv32_submit_job(uintptr_t mailbox_base, const rv32_vision_job_t *job)
{
    uint32_t status = read32(mailbox_base, MB_STATUS);
    if ((status & (MB_PENDING | MB_BUSY | MB_DONE | MB_ERROR)) != 0u) {
        return -1;
    }

    write32(mailbox_base, MB_INPUT_ADDR, job->input_addr);
    write32(mailbox_base, MB_OUTPUT_ADDR, job->output_addr);
    write32(mailbox_base, MB_TRANSFER_BYTES, job->transfer_bytes);
    write32(mailbox_base, MB_MODE, job->mode);
    write32(mailbox_base, MB_THRESHOLD, job->threshold);
    write32(mailbox_base, MB_JOB_ID, job->job_id);
    write32(mailbox_base, MB_COMMAND, MB_CMD_SUBMIT);
    return 0;
}

int rv32_wait_for_job(
    uintptr_t mailbox_base,
    uint32_t poll_limit,
    uint32_t *result,
    uint32_t *error_code
)
{
    for (uint32_t poll = 0; poll < poll_limit; ++poll) {
        uint32_t status = read32(mailbox_base, MB_STATUS);
        if ((status & MB_DONE) != 0u) {
            if (result != NULL) {
                *result = read32(mailbox_base, MB_RESULT);
            }
            if (error_code != NULL) {
                *error_code = 0u;
            }
            write32(mailbox_base, MB_COMMAND, MB_CMD_ACK);
            return 0;
        }
        if ((status & MB_ERROR) != 0u) {
            if (result != NULL) {
                *result = 0u;
            }
            if (error_code != NULL) {
                *error_code = read32(mailbox_base, MB_ERROR_CODE);
            }
            write32(mailbox_base, MB_COMMAND, MB_CMD_ACK);
            return -1;
        }
    }
    return -2;
}

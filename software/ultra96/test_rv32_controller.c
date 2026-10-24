#include "rv32_controller.h"

#include <stdio.h>

static uint32_t mailbox[16];
static uint32_t imem[4];
static uint32_t dmem[4];

#define CHECK(condition) do { if (!(condition)) { \
    fprintf(stderr, "FAIL: line %d: %s\n", __LINE__, #condition); return 1; \
} } while (0)

static int rejected(const uint32_t *instructions, size_t ni,
                    const uint32_t *data, size_t nd)
{
    mailbox[0x2c / 4] = 1; /* Simulate replacement of a running controller. */
    imem[0] = 0xfeed1234u;
    int result = rv32_boot_controller((uintptr_t)mailbox, (uintptr_t)imem,
        (uintptr_t)dmem, instructions, ni, data, nd);
    return result == RV32_BOOT_BAD_IMAGE && mailbox[0x2c / 4] == 0 &&
           imem[0] == 0xfeed1234u;
}

int main(void)
{
    const uint32_t instructions[] = {0x00000013u, 0x00100073u};
    const uint32_t data[] = {0xabcdef01u, 0x23456789u};
    CHECK(rejected(NULL, 0, NULL, 0));
    CHECK(rejected(NULL, 1, NULL, 0));
    CHECK(rejected(instructions, RV32_LOCAL_MEMORY_WORDS + 1u, NULL, 0));
    CHECK(rejected(instructions, 2, NULL, 1));
    CHECK(rejected(instructions, 2, data, RV32_LOCAL_MEMORY_WORDS + 1u));
    CHECK(rv32_boot_controller((uintptr_t)mailbox, (uintptr_t)imem,
        (uintptr_t)dmem, instructions, 2, data, 2) == RV32_BOOT_OK);
    CHECK(mailbox[0x2c / 4] == 1 && imem[0] == instructions[0] && dmem[1] == data[1]);
    CHECK(rv32_verify_memory_words((uintptr_t)dmem, instructions, 2) != 0);
    CHECK(rv32_boot_controller((uintptr_t)mailbox, (uintptr_t)imem,
        (uintptr_t)dmem, instructions, 2, NULL, 0) == RV32_BOOT_OK);
    puts("PASS: ARM boot helper rejects invalid/empty images while holding reset; valid images verify/release");
    return 0;
}

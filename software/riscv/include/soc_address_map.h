#pragma once

#include <stdint.h>

#define SOC_LOCAL_MEMORY_BASE 0x00000000u
#define SOC_LOCAL_MEMORY_SIZE 0x00010000u
#define SOC_VISION_ACCEL_BASE 0xA0000000u
#define SOC_VISION_ACCEL_SIZE 0x00001000u
#define SOC_AXI_DMA_BASE      0xA0010000u
#define SOC_AXI_DMA_SIZE      0x00010000u
#define SOC_MAILBOX_BASE      0xA0020000u
#define SOC_MAILBOX_SIZE      0x00001000u
#define SOC_HOST_IMEM_BASE    0xA0030000u
#define SOC_HOST_IMEM_SIZE    0x00010000u
#define SOC_HOST_DMEM_BASE    0xA0040000u
#define SOC_HOST_DMEM_SIZE    0x00010000u

static inline void mmio_write32(uint32_t base, uint32_t offset, uint32_t value)
{
    *(volatile uint32_t *)(uintptr_t)(base + offset) = value;
}

static inline uint32_t mmio_read32(uint32_t base, uint32_t offset)
{
    return *(volatile uint32_t *)(uintptr_t)(base + offset);
}

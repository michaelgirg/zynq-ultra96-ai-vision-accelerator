#pragma once
#include "vision_runtime.h"
vision_platform_t vision_vitis_platform(void);
/* Configures one standalone A53/GIC owner; generated SDT supplies the IRQ ID. */
int vision_vitis_irq_init(void);
/* Identity-mapped, exclusively reserved low-DDR arrays; validated before DMA. */
vision_dma_buffer_t vision_vitis_buffer(uint32_t *words, size_t bytes);

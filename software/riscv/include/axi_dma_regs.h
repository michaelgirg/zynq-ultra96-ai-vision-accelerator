#pragma once

// AMD AXI DMA simple-mode register offsets.
#define DMA_MM2S_DMACR       0x000u
#define DMA_MM2S_DMASR       0x004u
#define DMA_MM2S_SA          0x018u
#define DMA_MM2S_LENGTH      0x028u
#define DMA_S2MM_DMACR       0x030u
#define DMA_S2MM_DMASR       0x034u
#define DMA_S2MM_DA          0x048u
#define DMA_S2MM_LENGTH      0x058u

#define DMA_DMACR_RUNSTOP    0x00000001u
#define DMA_DMACR_RESET      0x00000004u
#define DMA_DMASR_HALTED     0x00000001u
#define DMA_DMASR_IDLE       0x00000002u
#define DMA_DMASR_ERROR_MASK 0x00000770u
#define DMA_DMASR_IOC_IRQ    0x00001000u
#define DMA_DMASR_IRQ_MASK   0x00007000u

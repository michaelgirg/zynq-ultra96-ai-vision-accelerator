#include "vision_platform_vitis.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xtime_l.h"

static int read32(void *c, uintptr_t address, uint32_t *v)
{ (void)c; *v = Xil_In32((UINTPTR)address); return 0; }
static int write32(void *c, uintptr_t address, uint32_t v)
{ (void)c; Xil_Out32((UINTPTR)address, v); return 0; }
static int clean(void *c, void *address, size_t n)
{ (void)c; Xil_DCacheFlushRange((INTPTR)address, (INTPTR)n); return 0; }
static int invalidate(void *c, void *address, size_t n)
{ (void)c; Xil_DCacheInvalidateRange((INTPTR)address, (INTPTR)n); return 0; }
static void barrier_cb(void *c) { (void)c; __asm__ volatile("dsb sy" ::: "memory"); }
static uint64_t ticks(void *c)
{ XTime t; (void)c; XTime_GetTime(&t); return (uint64_t)t; }

vision_platform_t vision_vitis_platform(void)
{
    vision_platform_t p = {NULL, read32, write32, clean, invalidate, barrier_cb,
        ticks, COUNTS_PER_SECOND, "vitis-a53-baremetal", 1};
    return p;
}
vision_dma_buffer_t vision_vitis_buffer(uint32_t *words, size_t bytes)
{
    vision_dma_buffer_t b = {words, 0, bytes};
    if ((uintptr_t)words <= UINT32_MAX) b.physical = (uint32_t)(uintptr_t)words;
    return b;
}

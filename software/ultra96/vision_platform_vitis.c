#include "vision_platform_vitis.h"
#include "xil_io.h"
#include "xil_cache.h"
#include "xiltimer.h"
#include "xparameters.h"
#include "xscugic.h"
#include "xil_exception.h"
#include "soc_address_map.h"
#include "job_mailbox.h"
#include "vision_hw_config.h" /* Generated from the platform SDT, not a fixture. */

#if XPAR_DMA_BASEADDR != SOC_AXI_DMA_BASE || XPAR_PRE_BASEADDR != SOC_VISION_ACCEL_BASE || \
    XPAR_MAILBOX_BASEADDR != SOC_MAILBOX_BASE || XPAR_RV32_BASEADDR != SOC_HOST_IMEM_BASE
#error "Generated BSP does not match the canonical SoC address map"
#endif

static XScuGic gic;
static volatile uint32_t irq_causes;
static int irq_ready;

static uint64_t mask_irqs(void)
{
    uint64_t saved;
    __asm__ volatile("mrs %0, daif\nmsr daifset, #2" : "=r"(saved) :: "memory");
    return saved;
}
static void restore_irqs(uint64_t saved)
{ __asm__ volatile("msr daif, %0" :: "r"(saved) : "memory"); }
static void mailbox_isr(void *unused)
{
    uint32_t cause;
    (void)unused;
    cause = Xil_In32(SOC_MAILBOX_BASE + MAILBOX_REG_IRQ_STATUS) &
        Xil_In32(SOC_MAILBOX_BASE + MAILBOX_REG_IRQ_ENABLE) & 7u;
    irq_causes |= cause;
    Xil_Out32(SOC_MAILBOX_BASE + MAILBOX_REG_IRQ_STATUS, cause);
    __asm__ volatile("dsb sy" ::: "memory");
    /* Never ACK the job here: main must snapshot and validate ownership first. */
}

int vision_vitis_irq_init(void)
{
    XScuGic_Config *config = XScuGic_LookupConfig(XPAR_XSCUGIC_0_BASEADDR);
    if (!config || XScuGic_CfgInitialize(&gic, config, config->CpuBaseAddress) != XST_SUCCESS)
        return VISION_IO_ERROR;
    Xil_Out32(SOC_MAILBOX_BASE + MAILBOX_REG_IRQ_ENABLE, 0);
    XScuGic_SetPriorityTriggerType(&gic, VISION_MAILBOX_GIC_ID, 0xa0, 1);
    if (XScuGic_Connect(&gic, VISION_MAILBOX_GIC_ID, mailbox_isr, NULL) != XST_SUCCESS)
        return VISION_IO_ERROR;
    Xil_ExceptionInit();
    Xil_ExceptionRegisterHandler(XIL_EXCEPTION_ID_INT,
        (Xil_ExceptionHandler)XScuGic_InterruptHandler, &gic);
    XScuGic_Enable(&gic, VISION_MAILBOX_GIC_ID);
    irq_ready = 1;
    Xil_ExceptionEnable();
    return VISION_OK;
}

static int irq_prepare(void *unused)
{
    uint64_t saved;
    (void)unused;
    if (!irq_ready || Xil_In32(SOC_MAILBOX_BASE + MAILBOX_REG_IRQ_ENABLE)) return -1;
    saved = mask_irqs();
    irq_causes = 0;
    XScuGic_DistWriteReg(&gic, XSCUGIC_PENDING_CLR_OFFSET +
        (VISION_MAILBOX_GIC_ID / 32u) * 4u, 1u << (VISION_MAILBOX_GIC_ID % 32u));
    __asm__ volatile("dsb sy" ::: "memory");
    restore_irqs(saved);
    return 0;
}

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

static int irq_wait(void *unused, uint32_t *causes, uint64_t timeout, uint32_t limit)
{
    uint64_t start = ticks(unused);
    *causes = 0;
    for (uint32_t i = 0; i < limit; ++i) {
        uint64_t saved = mask_irqs();
        *causes = irq_causes;
        irq_causes = 0;
        restore_irqs(saved);
        if (*causes) return VISION_OK;
        if (ticks(unused) - start >= timeout) break;
    }
    return VISION_DEADLINE;
}

vision_platform_t vision_vitis_platform(void)
{
    vision_platform_t p = {NULL, read32, write32, clean, invalidate, barrier_cb,
        ticks, COUNTS_PER_SECOND, "vitis-a53-baremetal", 1, irq_prepare, irq_wait};
    return p;
}
vision_dma_buffer_t vision_vitis_buffer(uint32_t *words, size_t bytes)
{
    vision_dma_buffer_t b = {words, 0, bytes};
    if ((uintptr_t)words <= UINT32_MAX) b.physical = (uint32_t)(uintptr_t)words;
    return b;
}

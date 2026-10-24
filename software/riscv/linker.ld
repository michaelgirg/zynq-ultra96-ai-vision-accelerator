OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 32K
    DMEM (rwx) : ORIGIN = 0x00008000, LENGTH = 32K
}

SECTIONS
{
    /DISCARD/ :
    {
        *(.note .note.*)
    }

    .text : ALIGN(4)
    {
        KEEP(*(.init))
        *(.text .text.*)
    } > IMEM

    .data : ALIGN(4)
    {
        /* Harvard core: loads access DMEM, including read-only constants. */
        *(.rodata .rodata.*)
        *(.srodata .srodata.*)
        __global_pointer$ = . + 0x800;
        *(.sdata .sdata.*)
        *(.data .data.*)
    } > DMEM

    .bss (NOLOAD) : ALIGN(4)
    {
        _bss_start = .;
        *(.sbss .sbss.*)
        *(.bss .bss.*)
        *(COMMON)
        . = ALIGN(4);
        _bss_end = .;
    } > DMEM

    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);
    ASSERT(_bss_end <= _stack_top - 1024, "RV32 firmware leaves less than 1 KiB for stack")
}

    .section .init, "ax", @progbits
    .globl _start
    .type _start, @function
_start:
    la sp, _stack_top

    // Linker relaxation can otherwise turn this into `mv gp,gp`, leaving the
    // global pointer uninitialized before any C code executes.
    .option push
    .option norelax
    la gp, __global_pointer$
    .option pop

    la t0, _bss_start
    la t1, _bss_end
1:
    bgeu t0, t1, 2f
    sw zero, 0(t0)
    addi t0, t0, 4
    j 1b
2:
    call main
3:
    ebreak
    j 3b
    .size _start, .-_start

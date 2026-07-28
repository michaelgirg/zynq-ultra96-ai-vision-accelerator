# RV32IM synthesis-retention program.
#
# This starts with the passing RV32I smoke sequence and then executes all eight
# RV32M operations. It is used for synthesis reports, not as a replacement for
# the self-checking simulation testbenches.

    lui   x1, 0x12345
    auipc x2, 0
    addi  x3, x0, 5
    addi  x4, x0, 7
    add   x5, x3, x4
    sub   x6, x4, x3
    slli  x7, x3, 2
    srli  x8, x7, 1
    addi  x9, x0, -16
    srai  x10, x9, 2
    slt   x11, x9, x3
    sltu  x12, x9, x3
    xor   x13, x3, x4
    or    x14, x3, x4
    and   x15, x3, x4

    sw    x5, 0(x0)
    sb    x9, 4(x0)
    lb    x16, 4(x0)
    lbu   x17, 4(x0)
    sh    x1, 6(x0)
    lh    x18, 6(x0)
    lhu   x19, 6(x0)
    lw    x20, 0(x0)

    beq   x20, x5, 1f
    addi  x31, x0, 1
1:
    bne   x3, x4, 2f
    addi  x31, x0, 2
2:
    blt   x9, x3, 3f
    addi  x31, x0, 3
3:
    bge   x4, x3, 4f
    addi  x31, x0, 4
4:
    bltu  x3, x9, 5f
    addi  x31, x0, 5
5:
    bgeu  x9, x3, 6f
    addi  x31, x0, 6
6:
    jal   x21, 7f
    addi  x31, x0, 7
7:
    addi  x22, x0, 161
    jalr  x23, 0(x22)
    addi  x31, x0, 8

    # JALR lands here at byte address 160.
    mul    x24, x3, x4
    mulh   x25, x9, x4
    mulhsu x26, x9, x4
    mulhu  x27, x1, x4
    div    x28, x9, x3
    divu   x29, x1, x3
    rem    x30, x9, x3
    remu   x24, x1, x3

    fence
    ebreak

`timescale 1ns/1ps

// Pipelined RV32M integration test.
//
// Drives every M-extension operation through the five-stage core and checks the
// architectural writeback. Unlike the single-cycle M test, each MUL/DIV here
// occupies EX for multiple cycles and stalls the pipeline via muldiv_unit ->
// pipeline_control (pc_stall / stall_if_id / stall_id_ex / flush_ex_mem). The
// program deliberately keeps every M instruction independent (sources x1..x5,
// destinations x10..x23) so a green run isolates the multi-cycle EX handshake.
module core_pipeline_m_tb;
    import rv32i_pkg::*;

    localparam int CLK_PERIOD = 10;
    localparam int MAX_CYCLES = 800;

    logic clk;
    logic rst;
    logic [31:0] current_pc;
    logic [31:0] instruction;
    logic halted;
    logic illegal_instruction;
    logic instruction_fault;
    logic data_fault;

    int errors;
    int cycles;

    core_pipeline #(
        .IMEM_WORDS(64),
        .DMEM_WORDS(64)
    ) dut (
        .clk_i                 (clk),
        .rst_i                 (rst),
        .current_pc_o          (current_pc),
        .instruction_o         (instruction),
        .halted_o              (halted),
        .illegal_instruction_o (illegal_instruction),
        .instruction_fault_o   (instruction_fault),
        .data_fault_o          (data_fault)
    );

    initial clk = 1'b0;
    always #(CLK_PERIOD / 2) clk = ~clk;

    function automatic logic [31:0] encode_m(
        input muldiv_op_t operation,
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        return {7'b0000001, rs2, rs1, operation, rd, OP_REG};
    endfunction

    function automatic logic [31:0] encode_addi(
        input logic [11:0] imm,
        input logic [4:0]  rs1,
        input logic [4:0]  rd
    );
        return {imm, rs1, 3'b000, rd, OP_IMM};
    endfunction

    task automatic check_value(
        input logic [31:0] actual,
        input logic [31:0] expected,
        input string name
    );
        if (actual !== expected) begin
            $error("%s: expected %08h, got %08h", name, expected, actual);
            errors++;
        end
    endtask

    task automatic write_imem_word(
        input int unsigned word_index,
        input logic [31:0] value
    );
        dut.u_imem.mem[word_index / 4][(word_index % 4) * 32 +: 32] = value;
    endtask

    task automatic reset_core;
        rst = 1'b1;
        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;
    endtask

    initial begin
        errors = 0;
        cycles = 0;

        // One of every RV32M operation, then the required divide corner cases.
        write_imem_word(0, encode_m(MULDIV_MUL,    5'd2, 5'd1, 5'd10));
        write_imem_word(1, encode_m(MULDIV_MULH,   5'd2, 5'd3, 5'd11));
        write_imem_word(2, encode_m(MULDIV_MULHSU, 5'd4, 5'd1, 5'd12));
        write_imem_word(3, encode_m(MULDIV_MULHU,  5'd4, 5'd4, 5'd13));
        write_imem_word(4, encode_m(MULDIV_DIV,    5'd2, 5'd1, 5'd14));
        write_imem_word(5, encode_m(MULDIV_DIVU,   5'd2, 5'd4, 5'd15));
        write_imem_word(6, encode_m(MULDIV_REM,    5'd2, 5'd1, 5'd16));
        write_imem_word(7, encode_m(MULDIV_REMU,   5'd2, 5'd4, 5'd17));

        // Required architectural divide corner cases.
        write_imem_word(8,  encode_m(MULDIV_DIV,  5'd4, 5'd3, 5'd18));  // overflow
        write_imem_word(9,  encode_m(MULDIV_REM,  5'd4, 5'd3, 5'd19));  // overflow
        write_imem_word(10, encode_m(MULDIV_DIV,  5'd5, 5'd1, 5'd20));  // /0
        write_imem_word(11, encode_m(MULDIV_DIVU, 5'd5, 5'd1, 5'd21));  // /0
        write_imem_word(12, encode_m(MULDIV_REM,  5'd5, 5'd1, 5'd22));  // %0
        write_imem_word(13, encode_m(MULDIV_REMU, 5'd5, 5'd1, 5'd23));  // %0

        // Forwarding after a multi-cycle EX op: the ADDI reads the MUL result
        // one instruction later, so it must be forwarded from EX/MEM (the MUL is
        // in MEM the cycle the ADDI reaches EX), not read stale from the regfile.
        write_imem_word(14, encode_m(MULDIV_MUL, 5'd2, 5'd1, 5'd24));  // x24 = -2*3 = -6
        write_imem_word(15, encode_addi(12'd1, 5'd24, 5'd25));         // x25 = x24 + 1

        // An M instruction targeting x0 must not change x0.
        write_imem_word(16, encode_m(MULDIV_MUL, 5'd2, 5'd1, 5'd0));
        write_imem_word(17, INSTRUCTION_EBREAK);

        reset_core();

        // Seed the source registers directly (keeps the test toolchain-free).
        dut.u_regfile.regs[1] = 32'hffff_fffe;  // -2
        dut.u_regfile.regs[2] = 32'd3;
        dut.u_regfile.regs[3] = 32'h8000_0000;  // signed minimum
        dut.u_regfile.regs[4] = 32'hffff_ffff;  // -1 signed, maximum unsigned
        dut.u_regfile.regs[5] = 32'b0;

        while (!halted && (cycles < MAX_CYCLES)) begin
            @(posedge clk);
            #1;
            cycles++;

            if (illegal_instruction || instruction_fault || data_fault) begin
                $error(
                    "Unexpected RV32M failure at PC %08h: illegal=%b instruction_fault=%b data_fault=%b",
                    current_pc, illegal_instruction, instruction_fault, data_fault);
                errors++;
                break;
            end
        end

        if (!halted) begin
            $error("Pipelined RV32M program did not halt within %0d cycles", MAX_CYCLES);
            errors++;
        end

        check_value(dut.u_regfile.regs[0],  32'h0000_0000, "x0");
        check_value(dut.u_regfile.regs[10], 32'hffff_fffa, "MUL");
        check_value(dut.u_regfile.regs[11], 32'hffff_fffe, "MULH");
        check_value(dut.u_regfile.regs[12], 32'hffff_fffe, "MULHSU");
        check_value(dut.u_regfile.regs[13], 32'hffff_fffe, "MULHU");
        check_value(dut.u_regfile.regs[14], 32'h0000_0000, "DIV");
        check_value(dut.u_regfile.regs[15], 32'h5555_5555, "DIVU");
        check_value(dut.u_regfile.regs[16], 32'hffff_fffe, "REM");
        check_value(dut.u_regfile.regs[17], 32'h0000_0000, "REMU");
        check_value(dut.u_regfile.regs[18], 32'h8000_0000, "DIV overflow");
        check_value(dut.u_regfile.regs[19], 32'h0000_0000, "REM overflow");
        check_value(dut.u_regfile.regs[20], 32'hffff_ffff, "DIV by zero");
        check_value(dut.u_regfile.regs[21], 32'hffff_ffff, "DIVU by zero");
        check_value(dut.u_regfile.regs[22], 32'hffff_fffe, "REM by zero");
        check_value(dut.u_regfile.regs[23], 32'hffff_fffe, "REMU by zero");
        check_value(dut.u_regfile.regs[24], 32'hffff_fffa, "MUL producer");
        check_value(dut.u_regfile.regs[25], 32'hffff_fffb, "ADDI forwarded from MUL");

        if (errors == 0) begin
            $display("PASS: core_pipeline_m_tb (%0d executed cycles)", cycles);
        end else begin
            $fatal(1, "FAIL: core_pipeline_m_tb had %0d errors", errors);
        end

        $finish;
    end

endmodule

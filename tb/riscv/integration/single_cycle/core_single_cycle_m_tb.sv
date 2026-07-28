`timescale 1ns/1ps

module core_single_cycle_m_tb;
    import rv32i_pkg::*;

    localparam int CLK_PERIOD = 10;
    localparam int MAX_CYCLES = 50;

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

    core_single_cycle #(
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

    task automatic reset_core;
        rst = 1'b1;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;
        #1;
    endtask

    initial begin
        errors = 0;
        cycles = 0;

        // Execute every RV32M operation through fetch, decode, register read,
        // the combinational M unit, and architectural writeback.
        dut.u_imem.mem[0]  = encode_m(MULDIV_MUL,    5'd2, 5'd1, 5'd10);
        dut.u_imem.mem[1]  = encode_m(MULDIV_MULH,   5'd2, 5'd3, 5'd11);
        dut.u_imem.mem[2]  = encode_m(MULDIV_MULHSU, 5'd4, 5'd1, 5'd12);
        dut.u_imem.mem[3]  = encode_m(MULDIV_MULHU,  5'd4, 5'd4, 5'd13);
        dut.u_imem.mem[4]  = encode_m(MULDIV_DIV,    5'd2, 5'd1, 5'd14);
        dut.u_imem.mem[5]  = encode_m(MULDIV_DIVU,   5'd2, 5'd4, 5'd15);
        dut.u_imem.mem[6]  = encode_m(MULDIV_REM,    5'd2, 5'd1, 5'd16);
        dut.u_imem.mem[7]  = encode_m(MULDIV_REMU,   5'd2, 5'd4, 5'd17);

        // Required architectural divide corner cases.
        dut.u_imem.mem[8]  = encode_m(MULDIV_DIV,  5'd4, 5'd3, 5'd18);
        dut.u_imem.mem[9]  = encode_m(MULDIV_REM,  5'd4, 5'd3, 5'd19);
        dut.u_imem.mem[10] = encode_m(MULDIV_DIV,  5'd5, 5'd1, 5'd20);
        dut.u_imem.mem[11] = encode_m(MULDIV_DIVU, 5'd5, 5'd1, 5'd21);
        dut.u_imem.mem[12] = encode_m(MULDIV_REM,  5'd5, 5'd1, 5'd22);
        dut.u_imem.mem[13] = encode_m(MULDIV_REMU, 5'd5, 5'd1, 5'd23);

        // An M instruction targeting x0 must not change x0.
        dut.u_imem.mem[14] = encode_m(MULDIV_MUL, 5'd2, 5'd1, 5'd0);
        dut.u_imem.mem[15] = INSTRUCTION_EBREAK;

        reset_core();

        // Initialize source registers after reset and before the first M
        // instruction reaches the rising edge. This keeps the integration
        // test independent of an external assembler toolchain.
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
                    current_pc,
                    illegal_instruction,
                    instruction_fault,
                    data_fault
                );
                errors++;
                break;
            end
        end

        if (!halted) begin
            $error("RV32M program did not halt within %0d cycles", MAX_CYCLES);
            errors++;
        end

        check_value(current_pc, 32'd60, "halt PC");
        check_value(instruction, INSTRUCTION_EBREAK, "halt instruction");
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

        if (errors == 0) begin
            $display("PASS: core_single_cycle_m_tb (%0d executed cycles)", cycles);
        end else begin
            $fatal(1, "FAIL: core_single_cycle_m_tb had %0d errors", errors);
        end

        $finish;
    end

endmodule

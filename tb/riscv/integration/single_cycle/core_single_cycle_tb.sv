`timescale 1ns/1ps

module core_single_cycle_tb;
    localparam int CLK_PERIOD = 10;
    localparam int MAX_CYCLES = 100;

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
        .IMEM_WORDS (64),
        .DMEM_WORDS (64),
        .IMEM_HEX   ("../../../tb/riscv/programs/smoke_test.hex")
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
        reset_core();

        while (!halted && (cycles < MAX_CYCLES)) begin
            @(posedge clk);
            #1;
            cycles++;

            if (illegal_instruction) begin
                $error("Unexpected illegal instruction at PC %08h: %08h",
                       current_pc, instruction);
                errors++;
                break;
            end

            if (instruction_fault || data_fault) begin
                $error(
                    "Unexpected core fault at PC %08h: instruction=%b data=%b",
                    current_pc,
                    instruction_fault,
                    data_fault
                );
                errors++;
                break;
            end
        end

        if (!halted) begin
            $error("Core did not halt within %0d cycles", MAX_CYCLES);
            errors++;
        end

        check_value(current_pc, 32'd164, "halt PC");
        check_value(instruction, 32'h0010_0073, "halt instruction");

        check_value(dut.u_regfile.regs[0],  32'h0000_0000, "x0");
        check_value(dut.u_regfile.regs[1],  32'h1234_5000, "x1 LUI");
        check_value(dut.u_regfile.regs[2],  32'h0000_0004, "x2 AUIPC");
        check_value(dut.u_regfile.regs[5],  32'h0000_000c, "x5 ADD");
        check_value(dut.u_regfile.regs[6],  32'h0000_0002, "x6 SUB");
        check_value(dut.u_regfile.regs[7],  32'h0000_0014, "x7 SLLI");
        check_value(dut.u_regfile.regs[8],  32'h0000_000a, "x8 SRLI");
        check_value(dut.u_regfile.regs[9],  32'hffff_fff0, "x9 negative ADDI");
        check_value(dut.u_regfile.regs[10], 32'hffff_fffc, "x10 SRAI");
        check_value(dut.u_regfile.regs[11], 32'h0000_0001, "x11 SLT");
        check_value(dut.u_regfile.regs[12], 32'h0000_0000, "x12 SLTU");
        check_value(dut.u_regfile.regs[13], 32'h0000_0002, "x13 XOR");
        check_value(dut.u_regfile.regs[14], 32'h0000_0007, "x14 OR");
        check_value(dut.u_regfile.regs[15], 32'h0000_0005, "x15 AND");
        check_value(dut.u_regfile.regs[16], 32'hffff_fff0, "x16 LB");
        check_value(dut.u_regfile.regs[17], 32'h0000_00f0, "x17 LBU");
        check_value(dut.u_regfile.regs[18], 32'h0000_5000, "x18 LH");
        check_value(dut.u_regfile.regs[19], 32'h0000_5000, "x19 LHU");
        check_value(dut.u_regfile.regs[20], 32'h0000_000c, "x20 LW");
        check_value(dut.u_regfile.regs[21], 32'd144, "x21 JAL link");
        check_value(dut.u_regfile.regs[22], 32'd161, "x22 JALR target");
        check_value(dut.u_regfile.regs[23], 32'd156, "x23 JALR link");
        check_value(dut.u_regfile.regs[31], 32'h0000_0000,
                    "x31 skipped control-flow instructions");

        check_value(dut.u_dmem.mem[0], 32'h0000_000c, "memory word store");
        check_value(dut.u_dmem.mem[1], 32'h5000_00f0,
                    "memory byte and halfword stores");

        // The core has no trap handler yet, so precise faults freeze the PC and
        // suppress architectural writes while reporting the cause.
        dut.u_imem.mem[0] = 32'hffff_ffff;
        reset_core();
        if (!halted || !illegal_instruction || instruction_fault || data_fault) begin
            $error("Illegal-instruction stop behavior was incorrect");
            errors++;
        end
        check_value(current_pc, 32'd0, "illegal instruction PC hold");

        // jalr x0, 2(x0): bit zero is cleared, but target 2 is not IALIGN=32.
        dut.u_imem.mem[0] = 32'h0020_0067;
        reset_core();
        if (!halted || !instruction_fault || illegal_instruction || data_fault) begin
            $error("Misaligned control-target behavior was incorrect");
            errors++;
        end
        check_value(current_pc, 32'd0, "misaligned jump PC hold");

        // lw x1, 1(x0) must fault rather than silently rounding the address.
        dut.u_imem.mem[0] = 32'h0010_2083;
        reset_core();
        if (!halted || !data_fault || illegal_instruction || instruction_fault) begin
            $error("Misaligned data-access behavior was incorrect");
            errors++;
        end
        check_value(current_pc, 32'd0, "misaligned load PC hold");

        // lw x1, -4(x0) is outside this core's local data memory.
        dut.u_imem.mem[0] = 32'hffc0_2083;
        reset_core();
        if (!halted || !data_fault || illegal_instruction || instruction_fault) begin
            $error("Out-of-range data-access behavior was incorrect");
            errors++;
        end
        check_value(current_pc, 32'd0, "out-of-range load PC hold");

        if (errors == 0) begin
            $display("PASS: core_single_cycle_tb (%0d executed cycles)", cycles);
        end else begin
            $fatal(1, "FAIL: core_single_cycle_tb had %0d errors", errors);
        end

        $finish;
    end

endmodule

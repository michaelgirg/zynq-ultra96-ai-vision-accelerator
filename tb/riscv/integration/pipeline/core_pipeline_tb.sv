`timescale 1ns/1ps

module core_pipeline_tb;
    localparam int CLK_PERIOD = 10;
    localparam int MAX_CYCLES = 1000;

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
        .IMEM_WORDS (64),
        .DMEM_WORDS (64),
        .IMEM_HEX   ("../../../tb/riscv/programs/smoke_test_lines.hex")
    ) dut (
        .clk_i                 (clk),
        .rst_i                 (rst),
        .current_pc_o          (current_pc),
        .instruction_o         (instruction),
        .halted_o              (halted),
        .illegal_instruction_o (illegal_instruction),
        .instruction_fault_o   (instruction_fault),
        .data_fault_o          (data_fault),
        .mmio_req_valid        (),
        .mmio_req_ready        (1'b0),
        .mmio_req_write        (),
        .mmio_req_addr         (),
        .mmio_req_wdata        (),
        .mmio_req_wstrb        (),
        .mmio_resp_valid       (1'b0),
        .mmio_resp_ready       (),
        .mmio_resp_rdata       (32'b0),
        .mmio_resp_fault       (1'b0)
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

    task automatic reset_core();
        rst = 1'b1;
        repeat (3) @(posedge clk);
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
                $error("Unexpected illegal instruction after %0d cycles at PC %08h: %08h",
                       cycles, current_pc, instruction);
                errors++;
                break;
            end

            if (instruction_fault || data_fault) begin
                $error("Unexpected pipeline fault after %0d cycles at PC %08h: instruction=%b data=%b",
                       cycles, current_pc, instruction_fault, data_fault);
                errors++;
                break;
            end
        end

        if (!halted) begin
            $error("Pipeline core did not halt within %0d cycles", MAX_CYCLES);
            errors++;
        end

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
        check_value(dut.u_regfile.regs[31], 32'h0000_0000, "x31 skipped control-flow instructions");

        // x16-x20 above are loaded after the program's SW/SB/SH operations,
        // so they verify the stored values through the D-cache. The backing
        // array is intentionally not checked here: a write-back cache may
        // still hold a correct dirty line when the program halts.

        if (errors == 0) begin
            $display("PASS: core_pipeline_tb (%0d executed cycles)", cycles);
        end else begin
            $fatal(1, "FAIL: core_pipeline_tb had %0d errors", errors);
        end

        $finish;
    end

endmodule

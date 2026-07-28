`timescale 1ns/1ps

module core_pipeline_cache_tb;
    import rv32i_pkg::*;

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
    int dirty_writebacks;
    logic saw_redirect_during_imiss;
    logic saw_muldiv_during_dmiss;

    core_pipeline #(
        .IMEM_WORDS       (128),
        .DMEM_WORDS       (128),
        .ICACHE_NUM_SETS  (2),
        .DCACHE_NUM_SETS  (2),
        .DCACHE_NUM_WAYS  (2),
        .IMEM_LATENCY     (8),
        .DMEM_LATENCY     (12)
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

    function automatic logic [31:0] encode_addi(
        input logic [11:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        encode_addi = {immediate, rs1, 3'b000, rd, OP_IMM};
    endfunction

    function automatic logic [31:0] encode_add(
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        encode_add = {7'b0000000, rs2, rs1, 3'b000, rd, OP_REG};
    endfunction

    function automatic logic [31:0] encode_mul(
        input logic [4:0] rs2,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        encode_mul = {7'b0000001, rs2, rs1, 3'b000, rd, OP_REG};
    endfunction

    function automatic logic [31:0] encode_lw(
        input logic [11:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        encode_lw = {immediate, rs1, 3'b010, rd, OP_LOAD};
    endfunction

    function automatic logic [31:0] encode_sw(
        input logic [11:0] immediate,
        input logic [4:0] rs2,
        input logic [4:0] rs1
    );
        encode_sw = {
            immediate[11:5], rs2, rs1, 3'b010,
            immediate[4:0], OP_STORE
        };
    endfunction

    function automatic logic [31:0] encode_beq(
        input logic [12:0] immediate,
        input logic [4:0] rs2,
        input logic [4:0] rs1
    );
        encode_beq = {
            immediate[12], immediate[10:5], rs2, rs1, 3'b000,
            immediate[4:1], immediate[11], OP_BRANCH
        };
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

    always @(posedge clk) begin
        if (rst) begin
            dirty_writebacks          <= 0;
            saw_redirect_during_imiss <= 1'b0;
            saw_muldiv_during_dmiss   <= 1'b0;
        end
        else begin
            if (dut.ex_redirect && dut.icache_stall)
                saw_redirect_during_imiss <= 1'b1;

            if (dut.mem_stall && dut.muldiv_active)
                saw_muldiv_during_dmiss <= 1'b1;

            if (dut.dmem_req_valid && dut.dmem_req_ready &&
                dut.dmem_req_write)
                dirty_writebacks <= dirty_writebacks + 1;
        end
    end

    initial begin
        errors = 0;
        cycles = 0;
        rst    = 1'b1;

        // The branch at PC=8 reaches EX as fetch discovers the wrong-path
        // line at PC=16. Redirect must beat the I-cache-only stall.
        #1;
        write_imem_word(0, encode_addi(12'd1, 5'd0, 5'd1));
        write_imem_word(1, encode_addi(12'd1, 5'd0, 5'd2));
        write_imem_word(2, encode_beq(13'd24, 5'd2, 5'd1));
        write_imem_word(3, encode_addi(12'd99, 5'd0, 5'd10));

        write_imem_word(4, encode_addi(12'd99, 5'd0, 5'd11));
        write_imem_word(5, encode_addi(12'd99, 5'd0, 5'd12));
        write_imem_word(6, encode_addi(12'd99, 5'd0, 5'd13));
        write_imem_word(7, encode_addi(12'd99, 5'd0, 5'd14));

        // Store miss overlaps a younger MUL. The following load and ADD also
        // verify that a cache response reaches MEM/WB before load forwarding.
        write_imem_word(8,  encode_addi(12'd5, 5'd0, 5'd3));
        write_imem_word(9,  encode_sw(12'd0, 5'd3, 5'd0));
        write_imem_word(10, encode_mul(5'd3, 5'd3, 5'd6));
        write_imem_word(11, encode_lw(12'd0, 5'd0, 5'd4));
        write_imem_word(12, encode_add(5'd3, 5'd4, 5'd5));

        // Addresses 0, 32, and 64 map to the same two-way set. The third line
        // forces the dirty address-zero line to write back before replacement.
        write_imem_word(13, encode_addi(12'd32, 5'd0, 5'd7));
        write_imem_word(14, encode_lw(12'd0, 5'd7, 5'd8));
        write_imem_word(15, encode_addi(12'd64, 5'd0, 5'd7));
        write_imem_word(16, encode_lw(12'd0, 5'd7, 5'd9));
        write_imem_word(17, INSTRUCTION_EBREAK);

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        while (!halted && (cycles < MAX_CYCLES)) begin
            @(posedge clk);
            #1;
            cycles++;

            if (illegal_instruction || instruction_fault || data_fault) begin
                $error("Unexpected fault after %0d cycles at PC %08h", cycles,
                       current_pc);
                errors++;
                break;
            end
        end

        if (!halted) begin
            $error("Cache integration program did not halt within %0d cycles",
                   MAX_CYCLES);
            errors++;
        end

        check_value(dut.u_regfile.regs[3],  32'd5,  "branch target result");
        check_value(dut.u_regfile.regs[4],  32'd5,  "load through D-cache");
        check_value(dut.u_regfile.regs[5],  32'd10, "dependent load result");
        check_value(dut.u_regfile.regs[6],  32'd25, "MUL held across D miss");
        check_value(dut.u_regfile.regs[8],  32'd0,  "first conflict load");
        check_value(dut.u_regfile.regs[9],  32'd0,  "second conflict load");

        for (int reg_index = 10; reg_index <= 14; reg_index++)
            check_value(dut.u_regfile.regs[reg_index], 32'd0,
                        "wrong-path register remained clear");

        check_value(dut.u_dmem.mem[0][31:0], 32'd5, "dirty line writeback");

        if (!saw_redirect_during_imiss) begin
            $error("Test never overlapped a redirect with an I-cache miss");
            errors++;
        end

        if (!saw_muldiv_during_dmiss) begin
            $error("Test never overlapped MUL/DIV execution with a D-cache miss");
            errors++;
        end

        if (dirty_writebacks != 1) begin
            $error("Expected one dirty writeback, observed %0d", dirty_writebacks);
            errors++;
        end

        if (errors == 0)
            $display("PASS: core_pipeline_cache_tb (%0d cycles)", cycles);
        else
            $fatal(1, "FAIL: core_pipeline_cache_tb had %0d errors", errors);

        $finish;
    end

endmodule

`timescale 1ns/1ps

module core_pipeline_cache_fault_tb;
    import rv32i_pkg::*;

    localparam int MAX_CYCLES = 300;

    logic clk;
    logic rst;

    logic ifault_halted;
    logic ifault_illegal;
    logic ifault_instruction_fault;
    logic ifault_data_fault;

    logic dfault_halted;
    logic dfault_illegal;
    logic dfault_instruction_fault;
    logic dfault_data_fault;

    logic saw_instruction_fault;
    logic saw_data_fault;
    int cycles;
    int errors;

    core_pipeline #(
        .IMEM_WORDS  (64),
        .DMEM_WORDS  (64),
        .IMEM_LATENCY(3),
        .DMEM_LATENCY(4)
    ) ifault_dut (
        .clk_i                 (clk),
        .rst_i                 (rst),
        .current_pc_o          (),
        .instruction_o         (),
        .halted_o              (ifault_halted),
        .illegal_instruction_o (ifault_illegal),
        .instruction_fault_o   (ifault_instruction_fault),
        .data_fault_o          (ifault_data_fault)
    );

    core_pipeline #(
        .IMEM_WORDS  (64),
        .DMEM_WORDS  (64),
        .IMEM_LATENCY(3),
        .DMEM_LATENCY(4)
    ) dfault_dut (
        .clk_i                 (clk),
        .rst_i                 (rst),
        .current_pc_o          (),
        .instruction_o         (),
        .halted_o              (dfault_halted),
        .illegal_instruction_o (dfault_illegal),
        .instruction_fault_o   (dfault_instruction_fault),
        .data_fault_o          (dfault_data_fault)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic logic [31:0] encode_addi(
        input logic [11:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        encode_addi = {immediate, rs1, 3'b000, rd, OP_IMM};
    endfunction

    function automatic logic [31:0] encode_lw(
        input logic [11:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        encode_lw = {immediate, rs1, 3'b010, rd, OP_LOAD};
    endfunction

    function automatic logic [31:0] encode_jal(
        input logic [20:0] immediate,
        input logic [4:0] rd
    );
        encode_jal = {
            immediate[20], immediate[10:1], immediate[11],
            immediate[19:12], rd, OP_JAL
        };
    endfunction

    task automatic write_ifault_imem_word(
        input int unsigned word_index,
        input logic [31:0] value
    );
        ifault_dut.u_imem.mem[word_index / 4][(word_index % 4) * 32 +: 32] = value;
    endtask

    task automatic write_dfault_imem_word(
        input int unsigned word_index,
        input logic [31:0] value
    );
        dfault_dut.u_imem.mem[word_index / 4][(word_index % 4) * 32 +: 32] = value;
    endtask

    always @(posedge clk) begin
        if (rst) begin
            saw_instruction_fault <= 1'b0;
            saw_data_fault        <= 1'b0;
        end
        else begin
            if (ifault_halted && ifault_instruction_fault)
                saw_instruction_fault <= 1'b1;

            if (dfault_halted && dfault_data_fault)
                saw_data_fault <= 1'b1;
        end
    end

    initial begin
        errors = 0;
        cycles = 0;
        rst    = 1'b1;

        #1;
        // A 64-word instruction memory ends at byte address 0xFF.
        write_ifault_imem_word(0, encode_jal(21'd256, 5'd0));

        // A load from byte address 0x100 is just outside a 64-word D-memory.
        write_dfault_imem_word(0, encode_addi(12'd256, 5'd0, 5'd1));
        write_dfault_imem_word(1, encode_lw(12'd0, 5'd1, 5'd2));
        write_dfault_imem_word(2, INSTRUCTION_EBREAK);

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        while (!(saw_instruction_fault && saw_data_fault) &&
               (cycles < MAX_CYCLES)) begin
            @(posedge clk);
            #1;
            cycles++;

            if (ifault_illegal || ifault_data_fault ||
                dfault_illegal || dfault_instruction_fault) begin
                $error("Unexpected fault type while testing cache faults");
                errors++;
                break;
            end
        end

        if (!saw_instruction_fault) begin
            $error("Out-of-range instruction refill did not raise a fault");
            errors++;
        end

        if (!saw_data_fault) begin
            $error("Out-of-range data refill did not raise a fault");
            errors++;
        end

        if (errors == 0)
            $display("PASS: core_pipeline_cache_fault_tb (%0d cycles)", cycles);
        else
            $fatal(1, "FAIL: core_pipeline_cache_fault_tb had %0d errors", errors);

        $finish;
    end

endmodule

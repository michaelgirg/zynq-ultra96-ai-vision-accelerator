`timescale 1ns/1ps

module core_pipeline_mmio_tb;
    import rv32i_pkg::*;

    localparam int MAX_CYCLES = 1000;

    logic clk;
    logic rst;
    logic [31:0] current_pc;
    logic halted;
    logic illegal_instruction;
    logic instruction_fault;
    logic data_fault;

    logic        mmio_req_valid;
    logic        mmio_req_ready;
    logic        mmio_req_write;
    logic [31:0] mmio_req_addr;
    logic [31:0] mmio_req_wdata;
    logic [3:0]  mmio_req_wstrb;
    logic        mmio_resp_valid;
    logic        mmio_resp_ready;
    logic [31:0] mmio_resp_rdata;
    logic        mmio_resp_fault;

    logic transaction_pending;
    int response_delay;
    int transactions;
    int local_requests;
    int cycles;
    int errors;

    core_pipeline #(
        .IMEM_WORDS  (64),
        .DMEM_WORDS  (64),
        .IMEM_LATENCY(3),
        .DMEM_LATENCY(4)
    ) dut (
        .clk_i                 (clk),
        .rst_i                 (rst),
        .current_pc_o          (current_pc),
        .instruction_o         (),
        .halted_o              (halted),
        .illegal_instruction_o (illegal_instruction),
        .instruction_fault_o   (instruction_fault),
        .data_fault_o          (data_fault),
        .mmio_req_valid        (mmio_req_valid),
        .mmio_req_ready        (mmio_req_ready),
        .mmio_req_write        (mmio_req_write),
        .mmio_req_addr         (mmio_req_addr),
        .mmio_req_wdata        (mmio_req_wdata),
        .mmio_req_wstrb        (mmio_req_wstrb),
        .mmio_resp_valid       (mmio_resp_valid),
        .mmio_resp_ready       (mmio_resp_ready),
        .mmio_resp_rdata       (mmio_resp_rdata),
        .mmio_resp_fault       (mmio_resp_fault)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    function automatic logic [31:0] encode_lui(
        input logic [19:0] immediate,
        input logic [4:0] rd
    );
        encode_lui = {immediate, rd, OP_LUI};
    endfunction

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

    task automatic write_imem_word(
        input int unsigned word_index,
        input logic [31:0] value
    );
        dut.u_imem.mem[word_index / 4][(word_index % 4) * 32 +: 32] = value;
    endtask

    task automatic fail(input string message);
        $error("%s", message);
        errors++;
    endtask

    always @(posedge clk) begin
        if (rst) begin
            mmio_req_ready <= 1'b0;
            mmio_resp_valid <= 1'b0;
            mmio_resp_rdata <= '0;
            mmio_resp_fault <= 1'b0;
            transaction_pending <= 1'b0;
            response_delay <= 0;
            transactions <= 0;
            local_requests <= 0;
        end
        else begin
            mmio_req_ready <= !transaction_pending && !mmio_resp_valid &&
                              (($urandom_range(0, 3) != 0));

            if (dut.dcache_req_valid)
                local_requests <= local_requests + 1;

            if (mmio_req_valid && mmio_req_ready) begin
                $display("MMIO[%0d] write=%0b addr=%08h data=%08h at %0t",
                         transactions, mmio_req_write, mmio_req_addr,
                         mmio_req_wdata, $time);
                transaction_pending <= 1'b1;
                mmio_req_ready <= 1'b0;
                response_delay <= $urandom_range(1, 5);

                if (mmio_req_wstrb != 4'b1111)
                    fail("MMIO store did not use full word strobes");

                case (transactions)
                    0: begin
                        if (!mmio_req_write || mmio_req_addr != 32'ha000_0000 ||
                            mmio_req_wdata != 32'h0000_0055)
                            fail("accelerator control store mismatch");
                        mmio_resp_rdata <= '0;
                    end

                    1: begin
                        if (mmio_req_write || mmio_req_addr != 32'ha000_0004)
                            fail("accelerator status load mismatch");
                        mmio_resp_rdata <= 32'h1234_5678;
                    end

                    2: begin
                        if (!mmio_req_write || mmio_req_addr != 32'ha002_0000 ||
                            mmio_req_wdata != 32'h1234_5679)
                            fail("mailbox completion store mismatch");
                        mmio_resp_rdata <= '0;
                    end

                    default: fail("duplicate or unexpected MMIO request");
                endcase

                transactions <= transactions + 1;
            end

            if (transaction_pending && !mmio_resp_valid) begin
                if (response_delay > 0)
                    response_delay <= response_delay - 1;
                else
                    mmio_resp_valid <= 1'b1;
            end

            if (mmio_resp_valid && mmio_resp_ready) begin
                mmio_resp_valid <= 1'b0;
                mmio_resp_rdata <= '0;
                transaction_pending <= 1'b0;
            end
        end
    end

    initial begin
        rst = 1'b1;
        errors = 0;
        cycles = 0;
        mmio_req_ready = 1'b0;
        mmio_resp_valid = 1'b0;
        mmio_resp_rdata = '0;
        mmio_resp_fault = 1'b0;
        transaction_pending = 1'b0;

        #1;
        write_imem_word(0, encode_lui(20'ha0000, 5'd1));
        write_imem_word(1, encode_addi(12'h055, 5'd0, 5'd2));
        write_imem_word(2, encode_sw(12'h000, 5'd2, 5'd1));
        write_imem_word(3, encode_lw(12'h004, 5'd1, 5'd3));
        write_imem_word(4, encode_addi(12'h001, 5'd3, 5'd4));
        write_imem_word(5, encode_lui(20'ha0020, 5'd5));
        write_imem_word(6, encode_sw(12'h000, 5'd4, 5'd5));
        write_imem_word(7, INSTRUCTION_EBREAK);

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        while (!halted && cycles < MAX_CYCLES) begin
            @(posedge clk);
            #1;
            cycles++;
            if (illegal_instruction || instruction_fault || data_fault) begin
                fail("unexpected processor fault during MMIO program");
                break;
            end
        end

        if (!halted)
            fail("MMIO program did not halt");
        if (transactions != 3)
            fail("MMIO program did not issue exactly three transactions");
        if (local_requests != 0)
            fail("MMIO program touched the D-cache request path");
        if (dut.u_regfile.regs[3] != 32'h1234_5678)
            fail("MMIO load did not write back expected data");
        if (dut.u_regfile.regs[4] != 32'h1234_5679)
            fail("dependent instruction used wrong MMIO load value");

        if (errors == 0)
            $display("PASS: core_pipeline_mmio_tb (%0d cycles, %0d transactions)",
                     cycles, transactions);
        else
            $fatal(1, "FAIL: core_pipeline_mmio_tb had %0d errors", errors);

        $finish;
    end

endmodule

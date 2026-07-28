`timescale 1ns/1ps

module rv32_pipeline_axi_top_tb;
    import rv32i_pkg::*;

    localparam int MAX_CYCLES = 2000;

    logic clk = 1'b0;
    logic rst = 1'b1;
    logic [31:0] current_pc;
    logic halted;
    logic illegal_instruction;
    logic instruction_fault;
    logic data_fault;

    logic [31:0] M_AXI_AWADDR;
    logic [2:0]  M_AXI_AWPROT;
    logic        M_AXI_AWVALID;
    logic        M_AXI_AWREADY;
    logic [31:0] M_AXI_WDATA;
    logic [3:0]  M_AXI_WSTRB;
    logic        M_AXI_WVALID;
    logic        M_AXI_WREADY;
    logic [1:0]  M_AXI_BRESP;
    logic        M_AXI_BVALID;
    logic        M_AXI_BREADY;
    logic [31:0] M_AXI_ARADDR;
    logic [2:0]  M_AXI_ARPROT;
    logic        M_AXI_ARVALID;
    logic        M_AXI_ARREADY;
    logic [31:0] M_AXI_RDATA;
    logic [1:0]  M_AXI_RRESP;
    logic        M_AXI_RVALID;
    logic        M_AXI_RREADY;

    logic        aw_captured;
    logic [31:0] aw_address;
    logic        w_captured;
    logic [31:0] w_data;
    logic [3:0]  w_strobes;
    integer transactions;
    integer local_requests;
    integer cycles;
    integer errors;

    always #5 clk = ~clk;

    rv32_pipeline_axi_top #(
        .IMEM_WORDS  (64),
        .DMEM_WORDS  (64),
        .IMEM_LATENCY(3),
        .DMEM_LATENCY(4)
    ) dut (
        .clk_i                 (clk),
        .rst_i                 (rst),
        .memory_rst_i          (rst),
        .imem_host_req_valid  (1'b0),
        .imem_host_req_ready  (),
        .imem_host_req_write  (1'b0),
        .imem_host_req_addr   ('0),
        .imem_host_req_wdata  ('0),
        .imem_host_req_wstrb  ('0),
        .imem_host_resp_valid (),
        .imem_host_resp_ready (1'b1),
        .imem_host_resp_rdata (),
        .imem_host_resp_fault (),
        .dmem_host_req_valid  (1'b0),
        .dmem_host_req_ready  (),
        .dmem_host_req_write  (1'b0),
        .dmem_host_req_addr   ('0),
        .dmem_host_req_wdata  ('0),
        .dmem_host_req_wstrb  ('0),
        .dmem_host_resp_valid (),
        .dmem_host_resp_ready (1'b1),
        .dmem_host_resp_rdata (),
        .dmem_host_resp_fault (),

        .current_pc_o          (current_pc),
        .instruction_o         (),
        .halted_o              (halted),
        .illegal_instruction_o (illegal_instruction),
        .instruction_fault_o   (instruction_fault),
        .data_fault_o          (data_fault),
        .*
    );

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
        dut.u_core.u_imem.mem[word_index] = value;
    endtask

    task automatic fail(input string message);
        begin
            $error("%s", message);
            errors = errors + 1;
        end
    endtask

    task automatic check_write_transaction;
        begin
            case (transactions)
                0: begin
                    if (aw_address != 32'hA000_0000 ||
                        w_data != 32'h0000_0055 || w_strobes != 4'b1111)
                        fail("accelerator control AXI write mismatch");
                end
                2: begin
                    if (aw_address != 32'hA002_0000 ||
                        w_data != 32'h1234_5679 || w_strobes != 4'b1111)
                        fail("mailbox AXI write mismatch");
                end
                default: fail("unexpected AXI write transaction");
            endcase
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            M_AXI_AWREADY <= 1'b0;
            M_AXI_WREADY <= 1'b0;
            M_AXI_BRESP <= 2'b00;
            M_AXI_BVALID <= 1'b0;
            M_AXI_ARREADY <= 1'b0;
            M_AXI_RDATA <= '0;
            M_AXI_RRESP <= 2'b00;
            M_AXI_RVALID <= 1'b0;
            aw_captured <= 1'b0;
            w_captured <= 1'b0;
            transactions <= 0;
            local_requests <= 0;
        end
        else begin
            M_AXI_AWREADY <= !aw_captured && !M_AXI_BVALID &&
                             ($urandom_range(0, 2) != 0);
            M_AXI_WREADY <= !w_captured && !M_AXI_BVALID &&
                            ($urandom_range(0, 2) != 0);
            M_AXI_ARREADY <= !M_AXI_RVALID &&
                             ($urandom_range(0, 2) != 0);

            if (dut.u_core.dcache_req_valid)
                local_requests <= local_requests + 1;

            if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                aw_captured <= 1'b1;
                aw_address <= M_AXI_AWADDR;
            end
            if (M_AXI_WVALID && M_AXI_WREADY) begin
                w_captured <= 1'b1;
                w_data <= M_AXI_WDATA;
                w_strobes <= M_AXI_WSTRB;
            end

            if (aw_captured && w_captured && !M_AXI_BVALID) begin
                check_write_transaction();
                transactions <= transactions + 1;
                M_AXI_BRESP <= 2'b00;
                M_AXI_BVALID <= 1'b1;
                aw_captured <= 1'b0;
                w_captured <= 1'b0;
            end
            else if (M_AXI_BVALID && M_AXI_BREADY) begin
                M_AXI_BVALID <= 1'b0;
            end

            if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                if (transactions != 1 || M_AXI_ARADDR != 32'hA000_0004)
                    fail("accelerator status AXI read mismatch");
                transactions <= transactions + 1;
                M_AXI_RDATA <= 32'h1234_5678;
                M_AXI_RRESP <= 2'b00;
                M_AXI_RVALID <= 1'b1;
            end
            else if (M_AXI_RVALID && M_AXI_RREADY) begin
                M_AXI_RVALID <= 1'b0;
            end
        end
    end

    initial begin
        errors = 0;
        cycles = 0;
        M_AXI_AWREADY = 1'b0;
        M_AXI_WREADY = 1'b0;
        M_AXI_BRESP = 2'b00;
        M_AXI_BVALID = 1'b0;
        M_AXI_ARREADY = 1'b0;
        M_AXI_RDATA = '0;
        M_AXI_RRESP = 2'b00;
        M_AXI_RVALID = 1'b0;
        aw_captured = 1'b0;
        w_captured = 1'b0;

        #1;
        write_imem_word(0, encode_lui(20'hA0000, 5'd1));
        write_imem_word(1, encode_addi(12'h055, 5'd0, 5'd2));
        write_imem_word(2, encode_sw(12'h000, 5'd2, 5'd1));
        write_imem_word(3, encode_lw(12'h004, 5'd1, 5'd3));
        write_imem_word(4, encode_addi(12'h001, 5'd3, 5'd4));
        write_imem_word(5, encode_lui(20'hA0020, 5'd5));
        write_imem_word(6, encode_sw(12'h000, 5'd4, 5'd5));
        write_imem_word(7, INSTRUCTION_EBREAK);

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        while (!halted && cycles < MAX_CYCLES) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
            if (illegal_instruction || instruction_fault || data_fault) begin
                fail("unexpected processor fault during AXI program");
                break;
            end
        end

        if (!halted)
            fail("AXI program did not halt");
        if (transactions != 3)
            fail("AXI program did not issue exactly three transactions");
        if (local_requests != 0)
            fail("AXI program touched the D-cache request path");
        if (dut.u_core.u_regfile.regs[3] != 32'h1234_5678)
            fail("AXI load did not write back expected data");
        if (dut.u_core.u_regfile.regs[4] != 32'h1234_5679)
            fail("dependent instruction used wrong AXI load value");

        if (errors == 0)
            $display("PASS: rv32_pipeline_axi_top_tb (%0d cycles, %0d AXI transactions)",
                     cycles, transactions);
        else
            $fatal(1, "FAIL: rv32_pipeline_axi_top_tb had %0d errors", errors);
        $finish;
    end
endmodule

`timescale 1ns/1ps

module rv32_vision_accelerator_tb;
    wire axi_timeout_o, axi_quarantined_o;
    wire [31:0] axi_fault_addr_o, axi_fault_info_o, axi_fault_wait_o;
    import rv32i_pkg::*;

    localparam int MAX_CYCLES = 3000;

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

    logic [31:0] S_AXIS_TDATA;
    logic [3:0]  S_AXIS_TKEEP;
    logic        S_AXIS_TVALID;
    logic        S_AXIS_TREADY;
    logic        S_AXIS_TLAST;
    logic [31:0] M_AXIS_TDATA;
    logic [3:0]  M_AXIS_TKEEP;
    logic        M_AXIS_TVALID;
    logic        M_AXIS_TREADY;
    logic        M_AXIS_TLAST;
    logic        irq;

    integer cycles;
    integer errors;
    integer axi_writes;
    integer axi_reads;
    integer output_pixels;

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

    // In hardware, AXI SmartConnect decodes the A000_0000 window and presents
    // the register offset to the accelerator. This direct connection models
    // that translation while retaining the full address on the RV32 master.
    axis_preprocess_vector_axi_lite #(
        .IMAGE_WIDTH (2),
        .IMAGE_HEIGHT(2),
        .IMAGE_PIXELS(4)
    ) accelerator (
        .S_AXI_ACLK   (clk),
        .S_AXI_ARESETN(!rst),
        .S_AXI_AWADDR (M_AXI_AWADDR[7:0]),
        .S_AXI_AWPROT (M_AXI_AWPROT),
        .S_AXI_AWVALID(M_AXI_AWVALID),
        .S_AXI_AWREADY(M_AXI_AWREADY),
        .S_AXI_WDATA  (M_AXI_WDATA),
        .S_AXI_WSTRB  (M_AXI_WSTRB),
        .S_AXI_WVALID (M_AXI_WVALID),
        .S_AXI_WREADY (M_AXI_WREADY),
        .S_AXI_BRESP  (M_AXI_BRESP),
        .S_AXI_BVALID (M_AXI_BVALID),
        .S_AXI_BREADY (M_AXI_BREADY),
        .S_AXI_ARADDR (M_AXI_ARADDR[7:0]),
        .S_AXI_ARPROT (M_AXI_ARPROT),
        .S_AXI_ARVALID(M_AXI_ARVALID),
        .S_AXI_ARREADY(M_AXI_ARREADY),
        .S_AXI_RDATA  (M_AXI_RDATA),
        .S_AXI_RRESP  (M_AXI_RRESP),
        .S_AXI_RVALID (M_AXI_RVALID),
        .S_AXI_RREADY (M_AXI_RREADY),
        .S_AXIS_TDATA,
        .S_AXIS_TKEEP,
        .S_AXIS_TVALID,
        .S_AXIS_TREADY,
        .S_AXIS_TLAST,
        .M_AXIS_TDATA,
        .M_AXIS_TKEEP,
        .M_AXIS_TVALID,
        .M_AXIS_TREADY,
        .M_AXIS_TLAST,
        .irq
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

    function automatic logic [31:0] encode_andi(
        input logic [11:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rd
    );
        encode_andi = {immediate, rs1, 3'b111, rd, OP_IMM};
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

    function automatic logic [31:0] encode_bne(
        input logic signed [12:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rs2
    );
        encode_bne = {
            immediate[12], immediate[10:5], rs2, rs1, 3'b001,
            immediate[4:1], immediate[11], OP_BRANCH
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

    task automatic send_pixel(
        input logic [7:0] pixel,
        input logic       last
    );
        begin
            @(negedge clk);
            S_AXIS_TDATA = {24'b0, pixel};
            S_AXIS_TKEEP = 4'b1111;
            S_AXIS_TLAST = last;
            S_AXIS_TVALID = 1'b1;
            do @(posedge clk); while (!S_AXIS_TREADY);
            @(negedge clk);
            S_AXIS_TVALID = 1'b0;
            S_AXIS_TLAST = 1'b0;
        end
    endtask

    always @(posedge clk) begin
        if (rst) begin
            axi_writes <= 0;
            axi_reads <= 0;
            output_pixels <= 0;
        end
        else begin
            if (M_AXI_AWVALID && M_AXI_AWREADY) begin
                axi_writes <= axi_writes + 1;
                if ((M_AXI_AWADDR & 32'hFFFF_F000) != 32'hA000_0000)
                    fail("RV32 write escaped the accelerator address window");
            end
            if (M_AXI_ARVALID && M_AXI_ARREADY) begin
                axi_reads <= axi_reads + 1;
                if ((M_AXI_ARADDR & 32'hFFFF_F000) != 32'hA000_0000)
                    fail("RV32 read escaped the accelerator address window");
            end
            if (M_AXIS_TVALID && M_AXIS_TREADY) begin
                case (output_pixels)
                    0: if (M_AXIS_TDATA[7:0] != 8'h00) fail("pixel 0 threshold mismatch");
                    1: if (M_AXIS_TDATA[7:0] != 8'hFF) fail("pixel 1 threshold mismatch");
                    2: if (M_AXIS_TDATA[7:0] != 8'hFF) fail("pixel 2 threshold mismatch");
                    3: if (M_AXIS_TDATA[7:0] != 8'h00) fail("pixel 3 threshold mismatch");
                    default: fail("accelerator produced too many pixels");
                endcase
                if (M_AXIS_TKEEP != 4'b1111)
                    fail("accelerator output TKEEP mismatch");
                if (M_AXIS_TLAST != (output_pixels == 3))
                    fail("accelerator output TLAST mismatch");
                output_pixels <= output_pixels + 1;
            end
        end
    end

    initial begin
        S_AXIS_TDATA = '0;
        S_AXIS_TKEEP = 4'b1111;
        S_AXIS_TVALID = 1'b0;
        S_AXIS_TLAST = 1'b0;
        M_AXIS_TREADY = 1'b1;

        wait (!rst);
        wait (S_AXIS_TREADY);
        send_pixel(8'd0,   1'b0);
        send_pixel(8'd100, 1'b0);
        send_pixel(8'd200, 1'b0);
        send_pixel(8'd99,  1'b1);
    end

    initial begin
        errors = 0;
        cycles = 0;

        #1;
        // Configure threshold=100 and mode=threshold, start one frame, poll
        // STATUS.busy until completion, then read telemetry and identity.
        write_imem_word(0,  encode_lui(20'hA0000, 5'd1));
        write_imem_word(1,  encode_addi(12'd100, 5'd0, 5'd2));
        write_imem_word(2,  encode_sw(12'h008, 5'd2, 5'd1));
        write_imem_word(3,  encode_addi(12'd0, 5'd0, 5'd2));
        write_imem_word(4,  encode_sw(12'h02C, 5'd2, 5'd1));
        write_imem_word(5,  encode_addi(12'd1, 5'd0, 5'd2));
        write_imem_word(6,  encode_sw(12'h000, 5'd2, 5'd1));
        write_imem_word(7,  encode_lw(12'h004, 5'd1, 5'd3));
        write_imem_word(8,  encode_andi(12'h001, 5'd3, 5'd3));
        write_imem_word(9,  encode_bne(-13'sd8, 5'd3, 5'd0));
        write_imem_word(10, encode_lw(12'h07C, 5'd1, 5'd4));
        write_imem_word(11, encode_lw(12'h070, 5'd1, 5'd5));
        write_imem_word(12, INSTRUCTION_EBREAK);

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        while (!halted && cycles < MAX_CYCLES) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
            if (illegal_instruction || instruction_fault || data_fault) begin
                fail("unexpected processor fault during accelerator program");
                break;
            end
        end

        if (!halted)
            fail("accelerator control program did not halt");
        if (output_pixels != 4)
            fail("accelerator did not emit the complete frame");
        if (dut.u_core.u_regfile.regs[4] != 32'd1)
            fail("processor did not read the completed frame counter");
        if (dut.u_core.u_regfile.regs[5] != 32'h5A42_4156)
            fail("processor did not read the accelerator identity register");
        if (axi_writes != 3)
            fail("processor issued an unexpected number of configuration writes");
        if (axi_reads < 3)
            fail("processor did not poll status and read telemetry");

        if (errors == 0)
            $display("PASS: RV32 controlled real accelerator (%0d cycles, %0d reads, %0d writes, %0d pixels)",
                     cycles, axi_reads, axi_writes, output_pixels);
        else
            $fatal(1, "FAIL: rv32_vision_accelerator_tb had %0d errors", errors);
        $finish;
    end
endmodule

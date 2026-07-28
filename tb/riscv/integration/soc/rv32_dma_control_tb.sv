`timescale 1ns/1ps

module rv32_dma_control_tb;
    import rv32i_pkg::*;

    localparam int MAX_CYCLES = 50000;

    logic clk = 1'b0;
    logic rst = 1'b1;
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

    logic        accel_awready;
    logic        accel_wready;
    logic [1:0]  accel_bresp;
    logic        accel_bvalid;
    logic        accel_arready;
    logic [31:0] accel_rdata;
    logic [1:0]  accel_rresp;
    logic        accel_rvalid;

    logic [31:0] dma_stream_data;
    logic [3:0]  dma_stream_keep;
    logic        dma_stream_valid;
    logic        dma_stream_ready;
    logic        dma_stream_last;
    logic [31:0] processed_stream_data;
    logic [3:0]  processed_stream_keep;
    logic        processed_stream_valid;
    logic        processed_stream_ready;
    logic        processed_stream_last;
    logic        accelerator_irq;

    logic        local_aw_captured;
    logic [31:0] local_awaddr;
    logic        local_w_captured;
    logic [31:0] local_wdata;
    logic [3:0]  local_wstrb;
    logic        local_bvalid;
    logic [1:0]  local_bresp;
    logic        local_rvalid;
    logic [31:0] local_rdata;
    logic [1:0]  local_rresp;

    logic [31:0] mm2s_control;
    logic [31:0] mm2s_source_address;
    logic [31:0] mm2s_length;
    logic [31:0] s2mm_control;
    logic [31:0] s2mm_destination_address;
    logic [31:0] s2mm_length;
    logic        mm2s_active;
    logic        s2mm_active;
    integer      mm2s_index;
    integer      s2mm_index;
    logic [31:0] mailbox_completion;
    logic [31:0] mailbox_status;
    logic [31:0] mailbox_input_address;
    logic [31:0] mailbox_output_address;
    logic [31:0] mailbox_transfer_bytes;
    logic [31:0] mailbox_mode;
    logic [31:0] mailbox_threshold;
    logic [31:0] mailbox_job_id;
    logic [31:0] mailbox_result;
    logic [31:0] mailbox_error_code;
    bit          compiled_firmware;
    integer      cycles;
    integer      errors;

    wire accel_write_select =
        (M_AXI_AWADDR & 32'hFFFF_F000) == 32'hA000_0000;
    wire accel_read_select =
        (M_AXI_ARADDR & 32'hFFFF_F000) == 32'hA000_0000;
    wire local_awready = !local_aw_captured && !local_bvalid;
    wire local_wready = !local_w_captured && !local_bvalid;
    wire local_arready = !local_rvalid;

    always #5 clk = ~clk;

    rv32_pipeline_axi_top #(
        .IMEM_WORDS  (8192),
        .DMEM_WORDS  (16384),
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

        .current_pc_o          (),
        .instruction_o         (),
        .halted_o              (halted),
        .illegal_instruction_o (illegal_instruction),
        .instruction_fault_o   (instruction_fault),
        .data_fault_o          (data_fault),
        .*
    );

    // Focused SmartConnect model: accelerator requests are forwarded to the
    // real RTL; DMA and mailbox windows are implemented behaviorally below.
    assign M_AXI_AWREADY = accel_write_select ? accel_awready : local_awready;
    assign M_AXI_WREADY  = accel_write_select ? accel_wready  : local_wready;
    assign M_AXI_BRESP   = accel_write_select ? accel_bresp   : local_bresp;
    assign M_AXI_BVALID  = accel_write_select ? accel_bvalid  : local_bvalid;
    assign M_AXI_ARREADY = accel_read_select  ? accel_arready : local_arready;
    assign M_AXI_RDATA   = accel_read_select  ? accel_rdata   : local_rdata;
    assign M_AXI_RRESP   = accel_read_select  ? accel_rresp   : local_rresp;
    assign M_AXI_RVALID  = accel_read_select  ? accel_rvalid  : local_rvalid;

    axis_preprocess_vector_axi_lite #(
        .IMAGE_WIDTH (2),
        .IMAGE_HEIGHT(2),
        .IMAGE_PIXELS(4)
    ) accelerator (
        .S_AXI_ACLK   (clk),
        .S_AXI_ARESETN(!rst),
        .S_AXI_AWADDR (M_AXI_AWADDR[7:0]),
        .S_AXI_AWPROT (M_AXI_AWPROT),
        .S_AXI_AWVALID(M_AXI_AWVALID && accel_write_select),
        .S_AXI_AWREADY(accel_awready),
        .S_AXI_WDATA  (M_AXI_WDATA),
        .S_AXI_WSTRB  (M_AXI_WSTRB),
        .S_AXI_WVALID (M_AXI_WVALID && accel_write_select),
        .S_AXI_WREADY (accel_wready),
        .S_AXI_BRESP  (accel_bresp),
        .S_AXI_BVALID (accel_bvalid),
        .S_AXI_BREADY (M_AXI_BREADY && accel_write_select),
        .S_AXI_ARADDR (M_AXI_ARADDR[7:0]),
        .S_AXI_ARPROT (M_AXI_ARPROT),
        .S_AXI_ARVALID(M_AXI_ARVALID && accel_read_select),
        .S_AXI_ARREADY(accel_arready),
        .S_AXI_RDATA  (accel_rdata),
        .S_AXI_RRESP  (accel_rresp),
        .S_AXI_RVALID (accel_rvalid),
        .S_AXI_RREADY (M_AXI_RREADY && accel_read_select),
        .S_AXIS_TDATA (dma_stream_data),
        .S_AXIS_TKEEP (dma_stream_keep),
        .S_AXIS_TVALID(dma_stream_valid),
        .S_AXIS_TREADY(dma_stream_ready),
        .S_AXIS_TLAST (dma_stream_last),
        .M_AXIS_TDATA (processed_stream_data),
        .M_AXIS_TKEEP (processed_stream_keep),
        .M_AXIS_TVALID(processed_stream_valid),
        .M_AXIS_TREADY(processed_stream_ready),
        .M_AXIS_TLAST (processed_stream_last),
        .irq          (accelerator_irq)
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

    function automatic logic [31:0] encode_beq(
        input logic signed [12:0] immediate,
        input logic [4:0] rs1,
        input logic [4:0] rs2
    );
        encode_beq = {
            immediate[12], immediate[10:5], rs2, rs1, 3'b000,
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

    function automatic logic [31:0] dma_input_pixel(input integer index);
        case (index)
            0: dma_input_pixel = 32'd0;
            1: dma_input_pixel = 32'd100;
            2: dma_input_pixel = 32'd200;
            default: dma_input_pixel = 32'd99;
        endcase
    endfunction

    function automatic logic [31:0] local_read_data(input logic [31:0] address);
        logic [15:0] offset;
        begin
            offset = address[15:0];
            local_read_data = 32'b0;
            if ((address & 32'hFFFF_0000) == 32'hA001_0000) begin
                case (offset)
                    16'h0000: local_read_data = mm2s_control;
                    16'h0004: local_read_data = mm2s_active ? 32'h0 : 32'h2;
                    16'h0018: local_read_data = mm2s_source_address;
                    16'h0028: local_read_data = mm2s_length;
                    16'h0030: local_read_data = s2mm_control;
                    16'h0034: local_read_data = s2mm_active ? 32'h0 : 32'h2;
                    16'h0048: local_read_data = s2mm_destination_address;
                    16'h0058: local_read_data = s2mm_length;
                    default: local_read_data = 32'b0;
                endcase
            end
            else if ((address & 32'hFFFF_F000) == 32'hA002_0000) begin
                if (compiled_firmware) begin
                    case (address[11:0])
                        12'h004: local_read_data = mailbox_status;
                        12'h008: local_read_data = mailbox_input_address;
                        12'h00C: local_read_data = mailbox_output_address;
                        12'h010: local_read_data = mailbox_transfer_bytes;
                        12'h014: local_read_data = mailbox_mode;
                        12'h018: local_read_data = mailbox_threshold;
                        12'h01C: local_read_data = mailbox_job_id;
                        12'h020: local_read_data = mailbox_result;
                        12'h024: local_read_data = mailbox_error_code;
                        12'h028: local_read_data = 32'h5A42_4D42;
                        default: local_read_data = 32'b0;
                    endcase
                end
                else begin
                    local_read_data = mailbox_completion;
                end
            end
        end
    endfunction

    always @(posedge clk) begin
        if (rst) begin
            local_aw_captured <= 1'b0;
            local_awaddr <= '0;
            local_w_captured <= 1'b0;
            local_wdata <= '0;
            local_wstrb <= '0;
            local_bvalid <= 1'b0;
            local_bresp <= 2'b00;
            local_rvalid <= 1'b0;
            local_rdata <= '0;
            local_rresp <= 2'b00;
            mm2s_control <= '0;
            mm2s_source_address <= '0;
            mm2s_length <= '0;
            s2mm_control <= '0;
            s2mm_destination_address <= '0;
            s2mm_length <= '0;
            mm2s_active <= 1'b0;
            s2mm_active <= 1'b0;
            mm2s_index <= 0;
            s2mm_index <= 0;
            mailbox_completion <= '0;
            mailbox_status <= compiled_firmware ? 32'h1 : 32'h0;
            mailbox_input_address <= 32'h1000_0000;
            mailbox_output_address <= 32'h1000_1000;
            mailbox_transfer_bytes <= 32'd16;
            mailbox_mode <= 32'd0;
            mailbox_threshold <= 32'd100;
            mailbox_job_id <= 32'hCAFE_0001;
            mailbox_result <= '0;
            mailbox_error_code <= '0;
            dma_stream_data <= '0;
            dma_stream_keep <= 4'b1111;
            dma_stream_valid <= 1'b0;
            dma_stream_last <= 1'b0;
        end
        else begin
            if (!accel_write_select && M_AXI_AWVALID && M_AXI_AWREADY) begin
                local_aw_captured <= 1'b1;
                local_awaddr <= M_AXI_AWADDR;
            end
            if (!accel_write_select && M_AXI_WVALID && M_AXI_WREADY) begin
                local_w_captured <= 1'b1;
                local_wdata <= M_AXI_WDATA;
                local_wstrb <= M_AXI_WSTRB;
            end

            if (local_aw_captured && local_w_captured && !local_bvalid) begin
                local_bresp <= 2'b00;
                if (local_wstrb != 4'b1111) begin
                    local_bresp <= 2'b10;
                end
                else if ((local_awaddr & 32'hFFFF_0000) == 32'hA001_0000) begin
                    case (local_awaddr[15:0])
                        16'h0000: mm2s_control <= local_wdata;
                        16'h0018: mm2s_source_address <= local_wdata;
                        16'h0028: begin
                            mm2s_length <= local_wdata;
                            if (mm2s_control[0] && local_wdata != 0) begin
                                mm2s_active <= 1'b1;
                                mm2s_index <= 0;
                                dma_stream_data <= dma_input_pixel(0);
                                dma_stream_valid <= 1'b1;
                                dma_stream_last <= (local_wdata == 4);
                            end
                        end
                        16'h0030: s2mm_control <= local_wdata;
                        16'h0048: s2mm_destination_address <= local_wdata;
                        16'h0058: begin
                            s2mm_length <= local_wdata;
                            if (s2mm_control[0] && local_wdata != 0) begin
                                s2mm_active <= 1'b1;
                                s2mm_index <= 0;
                            end
                        end
                        default: local_bresp <= 2'b10;
                    endcase
                end
                else if ((local_awaddr & 32'hFFFF_F000) == 32'hA002_0000) begin
                    if (!compiled_firmware && local_awaddr[11:0] == 12'h000) begin
                        mailbox_completion <= local_wdata;
                    end
                    else if (compiled_firmware) begin
                        case (local_awaddr[11:0])
                            12'h000: begin
                                case (local_wdata)
                                    32'h2: begin
                                        if (mailbox_status == 32'h1)
                                            mailbox_status <= 32'h2;
                                        else
                                            local_bresp <= 2'b10;
                                    end
                                    32'h4: begin
                                        if (mailbox_status == 32'h2)
                                            mailbox_status <= 32'h4;
                                        else
                                            local_bresp <= 2'b10;
                                    end
                                    32'h8: begin
                                        if (mailbox_status == 32'h2)
                                            mailbox_status <= 32'h8;
                                        else
                                            local_bresp <= 2'b10;
                                    end
                                    default: local_bresp <= 2'b10;
                                endcase
                            end
                            12'h020: begin
                                if (mailbox_status == 32'h2)
                                    mailbox_result <= local_wdata;
                                else
                                    local_bresp <= 2'b10;
                            end
                            12'h024: begin
                                if (mailbox_status == 32'h2)
                                    mailbox_error_code <= local_wdata;
                                else
                                    local_bresp <= 2'b10;
                            end
                            default: local_bresp <= 2'b10;
                        endcase
                    end
                    else begin
                        local_bresp <= 2'b10;
                    end
                end
                else begin
                    local_bresp <= 2'b10;
                end
                local_aw_captured <= 1'b0;
                local_w_captured <= 1'b0;
                local_bvalid <= 1'b1;
            end
            else if (local_bvalid && M_AXI_BREADY && !accel_write_select) begin
                local_bvalid <= 1'b0;
            end

            if (!accel_read_select && M_AXI_ARVALID && M_AXI_ARREADY) begin
                local_rdata <= local_read_data(M_AXI_ARADDR);
                local_rresp <=
                    (((M_AXI_ARADDR & 32'hFFFF_0000) == 32'hA001_0000) ||
                     ((M_AXI_ARADDR & 32'hFFFF_F000) == 32'hA002_0000)) ?
                    2'b00 : 2'b10;
                local_rvalid <= 1'b1;
            end
            else if (local_rvalid && M_AXI_RREADY && !accel_read_select) begin
                local_rvalid <= 1'b0;
            end

            if (mm2s_active && dma_stream_valid && dma_stream_ready) begin
                if (mm2s_index + 1 >= (mm2s_length >> 2)) begin
                    mm2s_active <= 1'b0;
                    dma_stream_valid <= 1'b0;
                    dma_stream_last <= 1'b0;
                end
                else begin
                    mm2s_index <= mm2s_index + 1;
                    dma_stream_data <= dma_input_pixel(mm2s_index + 1);
                    dma_stream_last <= (mm2s_index + 2 >= (mm2s_length >> 2));
                end
            end

            if (s2mm_active && processed_stream_valid && processed_stream_ready) begin
                case (s2mm_index)
                    0: if (processed_stream_data[7:0] != 8'h00) fail("DMA output pixel 0 mismatch");
                    1: if (processed_stream_data[7:0] != 8'hFF) fail("DMA output pixel 1 mismatch");
                    2: if (processed_stream_data[7:0] != 8'hFF) fail("DMA output pixel 2 mismatch");
                    3: if (processed_stream_data[7:0] != 8'h00) fail("DMA output pixel 3 mismatch");
                    default: fail("DMA captured too many output pixels");
                endcase
                if (processed_stream_last != (s2mm_index == 3))
                    fail("DMA output TLAST mismatch");
                if (s2mm_index + 1 >= (s2mm_length >> 2)) begin
                    s2mm_active <= 1'b0;
                end
                else begin
                    s2mm_index <= s2mm_index + 1;
                end
            end
        end
    end

    assign processed_stream_ready = s2mm_active;

    initial begin
        errors = 0;
        cycles = 0;
        compiled_firmware = $test$plusargs("COMPILED_FIRMWARE");

        #1;
        if (compiled_firmware) begin
            $readmemh("../../../software/riscv/build/controller_imem.mem",
                      dut.u_core.u_imem.mem);
            $readmemh("../../../software/riscv/build/controller_dmem.mem",
                      dut.u_core.u_dmem.mem);
        end
        else begin
            // Firmware-style controller sequence: configure S2MM first,
            // configure MM2S, arm the accelerator, launch input DMA, poll
            // output DMA idle, inspect telemetry, and publish completion.
            write_imem_word(0,  encode_lui(20'hA0000, 5'd1));
            write_imem_word(1,  encode_lui(20'hA0010, 5'd6));
            write_imem_word(2,  encode_lui(20'hA0020, 5'd7));
            write_imem_word(3,  encode_addi(12'd100, 5'd0, 5'd2));
            write_imem_word(4,  encode_sw(12'h008, 5'd2, 5'd1));
            write_imem_word(5,  encode_addi(12'd0, 5'd0, 5'd2));
            write_imem_word(6,  encode_sw(12'h02C, 5'd2, 5'd1));
            write_imem_word(7,  encode_addi(12'd1, 5'd0, 5'd2));
            write_imem_word(8,  encode_sw(12'h030, 5'd2, 5'd6));
            write_imem_word(9,  encode_lui(20'h10001, 5'd3));
            write_imem_word(10, encode_sw(12'h048, 5'd3, 5'd6));
            write_imem_word(11, encode_addi(12'd16, 5'd0, 5'd4));
            write_imem_word(12, encode_sw(12'h058, 5'd4, 5'd6));
            write_imem_word(13, encode_sw(12'h000, 5'd2, 5'd6));
            write_imem_word(14, encode_lui(20'h10000, 5'd3));
            write_imem_word(15, encode_sw(12'h018, 5'd3, 5'd6));
            write_imem_word(16, encode_sw(12'h000, 5'd2, 5'd1));
            write_imem_word(17, encode_sw(12'h028, 5'd4, 5'd6));
            write_imem_word(18, encode_lw(12'h034, 5'd6, 5'd5));
            write_imem_word(19, encode_andi(12'h002, 5'd5, 5'd5));
            write_imem_word(20, encode_beq(-13'sd8, 5'd5, 5'd0));
            write_imem_word(21, encode_lw(12'h07C, 5'd1, 5'd8));
            write_imem_word(22, encode_lui(20'h00006, 5'd2));
            write_imem_word(23, encode_addi(12'd13, 5'd2, 5'd2));
            write_imem_word(24, encode_sw(12'h000, 5'd2, 5'd7));
            write_imem_word(25, INSTRUCTION_EBREAK);
        end

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        while (((compiled_firmware && mailbox_status != 32'h4 &&
                 mailbox_status != 32'h8) ||
                (!compiled_firmware && !halted)) && cycles < MAX_CYCLES) begin
            @(posedge clk);
            #1;
            cycles = cycles + 1;
            if (illegal_instruction || instruction_fault || data_fault) begin
                fail("unexpected processor fault during DMA control program");
                break;
            end
        end

        if (compiled_firmware) begin
            if (mailbox_status != 32'h4)
                fail("compiled firmware did not complete the mailbox job");
            if (mailbox_result != 32'h0000_600D || mailbox_error_code != 0)
                fail("compiled firmware reported an incorrect mailbox result");
            if (halted)
                fail("compiled controller unexpectedly halted after one job");
        end
        else if (!halted) begin
            fail("DMA control program did not halt");
        end
        if (mm2s_source_address != 32'h1000_0000 || mm2s_length != 32'd16)
            fail("MM2S programming mismatch");
        if (s2mm_destination_address != 32'h1000_1000 || s2mm_length != 32'd16)
            fail("S2MM programming mismatch");
        if (mm2s_active || s2mm_active)
            fail("DMA channels remained active after firmware completion");
        if (s2mm_index != 3)
            fail("S2MM did not capture all four processed pixels");
        if (!compiled_firmware && dut.u_core.u_regfile.regs[8] != 32'd1)
            fail("firmware did not observe one completed accelerator frame");
        if (!compiled_firmware && mailbox_completion != 32'h0000_600D)
            fail("firmware did not publish the completion mailbox value");

        if (errors == 0 && compiled_firmware)
            $display("PASS: compiled RV32 firmware completed DMA job (%0d cycles, mailbox=%08h)",
                     cycles, mailbox_result);
        else if (errors == 0)
            $display("PASS: RV32 DMA control flow (%0d cycles, mailbox=%08h)",
                     cycles, mailbox_completion);
        else
            $fatal(1, "FAIL: rv32_dma_control_tb had %0d errors", errors);
        $finish;
    end
endmodule

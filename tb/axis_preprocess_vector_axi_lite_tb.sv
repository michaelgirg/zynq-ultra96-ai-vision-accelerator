`timescale 1 ns / 100 ps

// Module: axis_preprocess_vector_axi_lite_tb
// Description:
//Verifies the selectable AXI4-Stream preprocessing top with AXI4-Lite control.

module axis_preprocess_vector_axi_lite_tb #(
    parameter int DATA_WIDTH = 8,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int C_S_AXI_ADDR_WIDTH = 8,
    parameter int C_AXIS_DATA_WIDTH = 32,
    parameter int C_AXIS_KEEP_WIDTH = C_AXIS_DATA_WIDTH / 8,
    parameter int TIMEOUT_CYCLES = 50000
);
    bind axis_conv3x3_vector4_preprocess vector_core_safety_sva #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .IMAGE_PIXELS(IMAGE_PIXELS),
        .FIFO_DEPTH(FIFO_DEPTH),
        .FIFO_PTR_WIDTH(FIFO_PTR_WIDTH),
        .FIFO_COUNT_WIDTH(FIFO_COUNT_WIDTH)
    ) vector_core_safety_sva_i (
        .aclk(aclk),
        .aresetn(aresetn),
        .clear_done(clear_done),
        .busy(busy),
        .done(done),
        .packet_error(packet_error),
        .input_fire(input_fire),
        .output_fire(output_fire),
        .fifo_rd_ptr(fifo_rd_ptr_r),
        .fifo_wr_ptr(fifo_wr_ptr_r),
        .fifo_count(fifo_count_r),
        .m_axis_tdata(m_axis_tdata),
        .m_axis_tkeep(m_axis_tkeep),
        .m_axis_tvalid(m_axis_tvalid),
        .m_axis_tready(m_axis_tready),
        .m_axis_tlast(m_axis_tlast)
    );

    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CTRL              = 8'h00;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_STATUS            = 8'h04;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_THRESHOLD         = 8'h08;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_IMAGE_PIXELS      = 8'h0c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_PIXELS_PER_CYCLE  = 8'h10;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_PROCESSING_CYCLES = 8'h14;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_MODE              = 8'h2c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K00          = 8'h30;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K01          = 8'h34;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K02          = 8'h38;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K10          = 8'h3c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K11          = 8'h40;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K12          = 8'h44;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K20          = 8'h48;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K21          = 8'h4c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_K22          = 8'h50;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_BIAS         = 8'h54;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_SHIFT        = 8'h58;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CONV_RELU_EN      = 8'h5c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_VECTOR_CFG_INDEX  = 8'h60;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_VECTOR_CFG_DATA   = 8'h64;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_VECTOR_CFG_COMMIT = 8'h68;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_VECTOR_CFG_VERSION = 8'h6c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_IP_ID              = 8'h70;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_IP_VERSION         = 8'h74;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_CAPABILITIES       = 8'h78;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_FRAME_COUNT        = 8'h7c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_ERROR_COUNT        = 8'h80;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_INPUT_STALL_CYCLES = 8'h84;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_OUTPUT_STALL_CYCLES = 8'h88;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_ERROR_STATUS       = 8'h8c;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_INT_STATUS         = 8'h90;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_INT_ENABLE         = 8'h94;
    localparam logic [C_S_AXI_ADDR_WIDTH-1:0] ADDR_PERF_CONTROL       = 8'h98;

    localparam int MODE_THRESHOLD = 0;
    localparam int MODE_SOBEL = 1;
    localparam int MODE_CONV3X3 = 2;
    localparam int MODE_VECTOR4 = 3;
    localparam int DIRECTED_FRAME_COUNT = 2;
    localparam int DIRECTED_OUTPUT_PIXELS = DIRECTED_FRAME_COUNT * IMAGE_PIXELS;
    localparam logic [C_AXIS_KEEP_WIDTH-1:0] PIXEL_KEEP = '1;

    logic                                      clk = 1'b0;
    logic                                      rstn;

    logic [C_S_AXI_ADDR_WIDTH-1:0]             s_axi_awaddr;
    logic [2:0]                                s_axi_awprot;
    logic                                      s_axi_awvalid;
    logic                                      s_axi_awready;
    logic [C_S_AXI_DATA_WIDTH-1:0]             s_axi_wdata;
    logic [(C_S_AXI_DATA_WIDTH/8)-1:0]         s_axi_wstrb;
    logic                                      s_axi_wvalid;
    logic                                      s_axi_wready;
    logic [1:0]                                s_axi_bresp;
    logic                                      s_axi_bvalid;
    logic                                      s_axi_bready;
    logic [C_S_AXI_ADDR_WIDTH-1:0]             s_axi_araddr;
    logic [2:0]                                s_axi_arprot;
    logic                                      s_axi_arvalid;
    logic                                      s_axi_arready;
    logic [C_S_AXI_DATA_WIDTH-1:0]             s_axi_rdata;
    logic [1:0]                                s_axi_rresp;
    logic                                      s_axi_rvalid;
    logic                                      s_axi_rready;

    logic [C_AXIS_DATA_WIDTH-1:0]              s_axis_tdata;
    logic [C_AXIS_KEEP_WIDTH-1:0]              s_axis_tkeep;
    logic                                      s_axis_tvalid;
    logic                                      s_axis_tready;
    logic                                      s_axis_tlast;

    logic [C_AXIS_DATA_WIDTH-1:0]              m_axis_tdata;
    logic [C_AXIS_KEEP_WIDTH-1:0]              m_axis_tkeep;
    logic                                      m_axis_tvalid;
    logic                                      m_axis_tready;
    logic                                      m_axis_tlast;
    logic                                      irq;

    logic [DATA_WIDTH-1:0]                     input_pixels [0:IMAGE_PIXELS-1];
    logic [C_AXIS_DATA_WIDTH-1:0]              expected_words [0:IMAGE_PIXELS-1];

    string input_mem_path = "generated/test_vectors/sample_000_input.mem";
    string expected_mem_path = "generated/test_vectors/sample_000_threshold.mem";

    int preprocess_mode = MODE_THRESHOLD;
    int output_count = 0;
    int mismatch_count = 0;

    logic [C_AXIS_DATA_WIDTH-1:0] held_tdata;
    logic [C_AXIS_KEEP_WIDTH-1:0] held_tkeep;
    logic                         held_tlast;
    logic                         was_stalled;
    logic                         ready_enable;
    int                           ready_pattern_count = 0;

    axis_preprocess_vector_axi_lite #(
        .C_S_AXI_DATA_WIDTH(C_S_AXI_DATA_WIDTH),
        .C_S_AXI_ADDR_WIDTH(C_S_AXI_ADDR_WIDTH),
        .C_AXIS_DATA_WIDTH(C_AXIS_DATA_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT)
    ) DUT (
        .S_AXI_ACLK(clk),
        .S_AXI_ARESETN(rstn),
        .S_AXI_AWADDR(s_axi_awaddr),
        .S_AXI_AWPROT(s_axi_awprot),
        .S_AXI_AWVALID(s_axi_awvalid),
        .S_AXI_AWREADY(s_axi_awready),
        .S_AXI_WDATA(s_axi_wdata),
        .S_AXI_WSTRB(s_axi_wstrb),
        .S_AXI_WVALID(s_axi_wvalid),
        .S_AXI_WREADY(s_axi_wready),
        .S_AXI_BRESP(s_axi_bresp),
        .S_AXI_BVALID(s_axi_bvalid),
        .S_AXI_BREADY(s_axi_bready),
        .S_AXI_ARADDR(s_axi_araddr),
        .S_AXI_ARPROT(s_axi_arprot),
        .S_AXI_ARVALID(s_axi_arvalid),
        .S_AXI_ARREADY(s_axi_arready),
        .S_AXI_RDATA(s_axi_rdata),
        .S_AXI_RRESP(s_axi_rresp),
        .S_AXI_RVALID(s_axi_rvalid),
        .S_AXI_RREADY(s_axi_rready),
        .S_AXIS_TDATA(s_axis_tdata),
        .S_AXIS_TKEEP(s_axis_tkeep),
        .S_AXIS_TVALID(s_axis_tvalid),
        .S_AXIS_TREADY(s_axis_tready),
        .S_AXIS_TLAST(s_axis_tlast),
        .M_AXIS_TDATA(m_axis_tdata),
        .M_AXIS_TKEEP(m_axis_tkeep),
        .M_AXIS_TVALID(m_axis_tvalid),
        .M_AXIS_TREADY(m_axis_tready),
        .M_AXIS_TLAST(m_axis_tlast),
        .irq(irq)
    );

    production_diag_sva production_diag_sva_i (
        .clk(clk),
        .rstn(rstn),
        .irq(irq),
        .error_status(DUT.error_status_r),
        .int_status(DUT.int_status_r),
        .int_enable(DUT.int_enable_r),
        .frame_count(DUT.frame_count_r),
        .error_count(DUT.error_count_r),
        .input_stall_cycles(DUT.input_stall_cycles_r),
        .output_stall_cycles(DUT.output_stall_cycles_r),
        .perf_clear_pulse(DUT.perf_clear_pulse),
        .frame_done_event(DUT.frame_done_event),
        .packet_error_event(DUT.packet_error_event),
        .write_error_event(DUT.write_error_event),
        .read_error_event(DUT.read_error_event),
        .input_stall_event(DUT.stream_busy && s_axis_tvalid && !s_axis_tready),
        .output_stall_event(m_axis_tvalid && !m_axis_tready)
    );

    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    function automatic logic [C_S_AXI_DATA_WIDTH-1:0] merge_bytes(
        input logic [C_S_AXI_DATA_WIDTH-1:0] current_value,
        input logic [C_S_AXI_DATA_WIDTH-1:0] new_value,
        input logic [(C_S_AXI_DATA_WIDTH/8)-1:0] strobes
    );
        logic [C_S_AXI_DATA_WIDTH-1:0] merged;
        merged = current_value;
        for (int byte_index = 0; byte_index < C_S_AXI_DATA_WIDTH/8; byte_index++) begin
            if (strobes[byte_index]) begin
                merged[byte_index*8 +: 8] = new_value[byte_index*8 +: 8];
            end
        end
        return merged;
    endfunction

    task automatic axi_write_skew_expect(
        input logic [C_S_AXI_ADDR_WIDTH-1:0] addr,
        input logic [C_S_AXI_DATA_WIDTH-1:0] data,
        input logic [(C_S_AXI_DATA_WIDTH/8)-1:0] strobes,
        input int unsigned aw_delay_cycles,
        input int unsigned w_delay_cycles,
        input logic [1:0] expected_resp
    );
        @(negedge clk);
        s_axi_bready <= 1'b0;

        fork
            begin
                repeat (aw_delay_cycles) @(posedge clk);
                @(negedge clk);
                s_axi_awaddr <= addr;
                s_axi_awvalid <= 1'b1;
                do begin
                    @(posedge clk);
                end while (!(s_axi_awvalid && s_axi_awready));
                @(negedge clk);
                s_axi_awvalid <= 1'b0;
            end
            begin
                repeat (w_delay_cycles) @(posedge clk);
                @(negedge clk);
                s_axi_wdata <= data;
                s_axi_wstrb <= strobes;
                s_axi_wvalid <= 1'b1;
                do begin
                    @(posedge clk);
                end while (!(s_axi_wvalid && s_axi_wready));
                @(negedge clk);
                s_axi_wvalid <= 1'b0;
            end
        join

        @(negedge clk);
        s_axi_bready <= 1'b1;

        while (s_axi_bvalid !== 1'b1) begin
            @(posedge clk);
        end

        if (s_axi_bresp !== expected_resp) begin
            mismatch_count++;
            $error(
                "AXI write response mismatch at addr 0x%02h: actual=%0b expected=%0b",
                addr,
                s_axi_bresp,
                expected_resp
            );
        end

        @(posedge clk);
        @(negedge clk);
        s_axi_bready <= 1'b0;
        s_axi_awaddr <= '0;
        s_axi_wdata <= '0;
        s_axi_wstrb <= '0;
    endtask

    task automatic axi_write_strb_expect(
        input logic [C_S_AXI_ADDR_WIDTH-1:0] addr,
        input logic [C_S_AXI_DATA_WIDTH-1:0] data,
        input logic [(C_S_AXI_DATA_WIDTH/8)-1:0] strobes,
        input logic [1:0] expected_resp
    );
        axi_write_skew_expect(addr, data, strobes, 0, 0, expected_resp);
    endtask

    task automatic axi_write_strb(
        input logic [C_S_AXI_ADDR_WIDTH-1:0] addr,
        input logic [C_S_AXI_DATA_WIDTH-1:0] data,
        input logic [(C_S_AXI_DATA_WIDTH/8)-1:0] strobes
    );
        axi_write_strb_expect(addr, data, strobes, 2'b00);
    endtask

    task automatic axi_write(
        input logic [C_S_AXI_ADDR_WIDTH-1:0] addr,
        input logic [C_S_AXI_DATA_WIDTH-1:0] data
    );
        axi_write_strb(addr, data, '1);
    endtask

    task automatic program_vector_config;
        int signed weights [0:3][0:8] = '{
            '{29, 104, 127, -115, -76, 58, -78, -92, -114},
            '{13, -13, -116, -49, -79, 15, -127, -26, 11},
            '{48, -11, -127, -111, -76, -35, 39, 126, 94},
            '{-60, -14, 114, -74, 108, 15, 29, 127, 83}
        };
        int signed biases [0:3] = '{11029, 17936, 257, -131};
        int shifts [0:3] = '{9, 7, 9, 9};
        logic [C_S_AXI_DATA_WIDTH-1:0] read_value;
        logic [31:0] config_words [0:43];
        string config_path;

        if ($value$plusargs("VECTOR_CONFIG_MEM=%s", config_path)) begin
            $readmemh(config_path, config_words);
            for (int filter_index = 0; filter_index < 4; filter_index++) begin
                for (int entry = 0; entry < 11; entry++) begin
                    if ($isunknown(config_words[filter_index * 11 + entry]))
                        $fatal(1, "Missing vector configuration word %0d", filter_index * 11 + entry);
                end
                for (int tap_index = 0; tap_index < 9; tap_index++)
                    weights[filter_index][tap_index] = $signed(config_words[filter_index * 11 + tap_index]);
                biases[filter_index] = $signed(config_words[filter_index * 11 + 9]);
                if (config_words[filter_index * 11 + 10][8] != 1'b1)
                    $fatal(1, "This classifier contract requires ReLU enabled");
                shifts[filter_index] = int'(config_words[filter_index * 11 + 10][4:0]);
            end
        end

        for (int filter_index = 0; filter_index < 4; filter_index++) begin
            for (int tap_index = 0; tap_index < 9; tap_index++) begin
                axi_write(
                    ADDR_VECTOR_CFG_INDEX,
                    C_S_AXI_DATA_WIDTH'((filter_index << 4) | tap_index)
                );
                axi_write(ADDR_VECTOR_CFG_DATA, C_S_AXI_DATA_WIDTH'(weights[filter_index][tap_index]));
            end
            axi_write(
                ADDR_VECTOR_CFG_INDEX,
                C_S_AXI_DATA_WIDTH'((filter_index << 4) | 9)
            );
            axi_write(ADDR_VECTOR_CFG_DATA, C_S_AXI_DATA_WIDTH'(biases[filter_index]));
            axi_write(
                ADDR_VECTOR_CFG_INDEX,
                C_S_AXI_DATA_WIDTH'((filter_index << 4) | 10)
            );
            axi_write(ADDR_VECTOR_CFG_DATA, C_S_AXI_DATA_WIDTH'((1 << 8) | shifts[filter_index]));
        end

        axi_write(ADDR_VECTOR_CFG_COMMIT, C_S_AXI_DATA_WIDTH'(1));
        axi_read(ADDR_VECTOR_CFG_VERSION, read_value);
        if (read_value !== C_S_AXI_DATA_WIDTH'(1)) begin
            mismatch_count++;
            $error("vector configuration version mismatch: actual=%0d expected=1", read_value);
        end

        axi_write(ADDR_VECTOR_CFG_INDEX, C_S_AXI_DATA_WIDTH'(0));
        axi_read(ADDR_VECTOR_CFG_DATA, read_value);
        if ($signed(read_value) !== weights[0][0]) begin
            mismatch_count++;
            $error("vector weight readback mismatch: actual=%0d expected=%0d", $signed(read_value), weights[0][0]);
        end
    endtask

    task automatic axi_read_expect(
        input logic [C_S_AXI_ADDR_WIDTH-1:0] addr,
        output logic [C_S_AXI_DATA_WIDTH-1:0] data,
        input logic [1:0] expected_resp
    );
        @(negedge clk);
        s_axi_araddr <= addr;
        s_axi_arvalid <= 1'b1;
        s_axi_rready <= 1'b1;

        @(posedge clk);
        @(negedge clk);
        s_axi_arvalid <= 1'b0;

        while (s_axi_rvalid !== 1'b1) begin
            @(posedge clk);
        end

        data = s_axi_rdata;
        if (s_axi_rresp !== expected_resp) begin
            mismatch_count++;
            $error(
                "AXI read response mismatch at addr 0x%02h: actual=%0b expected=%0b",
                addr,
                s_axi_rresp,
                expected_resp
            );
        end

        @(posedge clk);
        @(negedge clk);
        s_axi_rready <= 1'b0;
        s_axi_araddr <= '0;
    endtask

    task automatic axi_read(
        input logic [C_S_AXI_ADDR_WIDTH-1:0] addr,
        output logic [C_S_AXI_DATA_WIDTH-1:0] data
    );
        axi_read_expect(addr, data, 2'b00);
    endtask

    task automatic check_write_strobes;
        logic [31:0] read_value;
        logic [31:0] expected;
        logic [31:0] base_value;
        logic [31:0] update_value;

        base_value = 32'h1122_3344;
        update_value = 32'ha1b2_c3d4;

        axi_read(ADDR_THRESHOLD, read_value);
        if (read_value[7:0] !== 8'd128) begin
            mismatch_count++;
            $error("threshold reset mismatch before WSTRB test: actual=0x%02h", read_value[7:0]);
        end

        axi_write_strb(ADDR_THRESHOLD, 32'h0000_005a, 4'b0001);
        axi_write_strb(ADDR_THRESHOLD, 32'hffff_0000, 4'b1110);
        axi_read(ADDR_THRESHOLD, read_value);
        if (read_value[7:0] !== 8'h5a) begin
            mismatch_count++;
            $error("disabled threshold byte changed: actual=0x%02h expected=0x5a", read_value[7:0]);
        end

        axi_write_strb(ADDR_MODE, MODE_VECTOR4, 4'b0010);
        axi_read(ADDR_MODE, read_value);
        if (read_value[1:0] !== MODE_THRESHOLD) begin
            mismatch_count++;
            $error("disabled mode byte changed: actual=%0d expected=%0d", read_value[1:0], MODE_THRESHOLD);
        end

        for (int strobe_value = 0; strobe_value < 16; strobe_value++) begin
            axi_write_strb(ADDR_CONV_BIAS, base_value, 4'b1111);
            axi_write_strb(ADDR_CONV_BIAS, update_value, strobe_value[3:0]);
            axi_read(ADDR_CONV_BIAS, read_value);
            expected = merge_bytes(base_value, update_value, strobe_value[3:0]);
            if (read_value !== expected) begin
                mismatch_count++;
                $error(
                    "bias WSTRB mismatch: strb=0x%0h actual=0x%08h expected=0x%08h",
                    strobe_value[3:0],
                    read_value,
                    expected
                );
            end
        end

        axi_write(ADDR_VECTOR_CFG_INDEX, 32'd9);
        axi_write(ADDR_VECTOR_CFG_DATA, base_value);
        axi_write_strb(ADDR_VECTOR_CFG_DATA, update_value, 4'b0101);
        axi_read(ADDR_VECTOR_CFG_DATA, read_value);
        expected = merge_bytes(base_value, update_value, 4'b0101);
        if (read_value !== expected) begin
            mismatch_count++;
            $error(
                "vector bias WSTRB mismatch: actual=0x%08h expected=0x%08h",
                read_value,
                expected
            );
        end

        axi_write(ADDR_VECTOR_CFG_INDEX, 32'd10);
        axi_write(ADDR_VECTOR_CFG_DATA, 32'h0000_0109);
        axi_write_strb(ADDR_VECTOR_CFG_DATA, 32'h0000_0003, 4'b0001);
        axi_read(ADDR_VECTOR_CFG_DATA, read_value);
        if (read_value[8:0] !== 9'h103) begin
            mismatch_count++;
            $error("shift write corrupted ReLU: actual=0x%03h expected=0x103", read_value[8:0]);
        end

        axi_write_strb(ADDR_VECTOR_CFG_DATA, 32'h0000_0000, 4'b0010);
        axi_read(ADDR_VECTOR_CFG_DATA, read_value);
        if (read_value[8:0] !== 9'h003) begin
            mismatch_count++;
            $error("ReLU write corrupted shift: actual=0x%03h expected=0x003", read_value[8:0]);
        end

        axi_write_strb(ADDR_VECTOR_CFG_COMMIT, 32'd1, 4'b1110);
        axi_read(ADDR_VECTOR_CFG_VERSION, read_value);
        if (read_value !== 32'd0) begin
            mismatch_count++;
            $error("commit fired with WSTRB[0]=0: version=%0d", read_value);
        end

        axi_write_strb(ADDR_CTRL, 32'd1, 4'b1110);
        axi_read(ADDR_STATUS, read_value);
        if (read_value[3:0] !== 4'b0000) begin
            mismatch_count++;
            $error("CTRL command fired with WSTRB[0]=0: status=0x%08h", read_value);
        end

        $display("PASS: AXI4-Lite WSTRB preservation checks completed.");
    endtask

    task automatic check_axi_response_policy;
        logic [31:0] read_value;

        axi_write_strb_expect(ADDR_STATUS, 32'hffff_ffff, 4'hf, 2'b10);
        axi_write_strb_expect(8'h09, 32'h0000_00aa, 4'hf, 2'b10);
        axi_write_strb_expect(8'h9c, 32'h1234_5678, 4'hf, 2'b10);

        axi_read_expect(ADDR_CTRL, read_value, 2'b10);
        if (read_value !== 32'd0) begin
            mismatch_count++;
            $error("write-only CTRL returned nonzero data: 0x%08h", read_value);
        end

        axi_read_expect(ADDR_VECTOR_CFG_COMMIT, read_value, 2'b10);
        axi_read_expect(8'h09, read_value, 2'b10);
        axi_read_expect(8'h9c, read_value, 2'b10);

        axi_write_skew_expect(ADDR_THRESHOLD, 32'h0000_0066, 4'b0001, 0, 3, 2'b00);
        axi_read(ADDR_THRESHOLD, read_value);
        if (read_value[7:0] !== 8'h66) begin
            mismatch_count++;
            $error("AW-first write failed: threshold=0x%02h", read_value[7:0]);
        end

        axi_write_skew_expect(ADDR_THRESHOLD, 32'h0000_0077, 4'b0001, 3, 0, 2'b00);
        axi_read(ADDR_THRESHOLD, read_value);
        if (read_value[7:0] !== 8'h77) begin
            mismatch_count++;
            $error("W-first write failed: threshold=0x%02h", read_value[7:0]);
        end

        $display("PASS: AXI4-Lite response and AW/W ordering checks completed.");
    endtask

    task automatic send_pixel(
        input int pixel_index
    );
        begin
            s_axis_tdata  <= {{(C_AXIS_DATA_WIDTH-DATA_WIDTH){1'b0}}, input_pixels[pixel_index]};
            s_axis_tkeep  <= PIXEL_KEEP;
            s_axis_tvalid <= 1'b1;
            s_axis_tlast  <= (pixel_index == IMAGE_PIXELS - 1);

            do begin
                @(posedge clk);
            end while (s_axis_tready !== 1'b1);

            s_axis_tvalid <= 1'b0;
            s_axis_tlast  <= 1'b0;
            s_axis_tdata  <= '0;

            if (((pixel_index % 31) == 9) || ((pixel_index % 47) == 16)) begin
                @(posedge clk);
            end
        end
    endtask

    initial begin : provide_stimulus
        logic [C_S_AXI_DATA_WIDTH-1:0] read_value;
        logic [C_S_AXI_DATA_WIDTH-1:0] status_value;
        logic [C_S_AXI_DATA_WIDTH-1:0] measured_processing_cycles;
        bit expected_mem_overridden;

        void'($value$plusargs("INPUT_MEM=%s", input_mem_path));
        expected_mem_overridden = $value$plusargs("EXPECTED_MEM=%s", expected_mem_path);
        void'($value$plusargs("MODE=%d", preprocess_mode));

        if (!expected_mem_overridden) begin
            case (preprocess_mode)
                MODE_THRESHOLD: expected_mem_path = "generated/test_vectors/sample_000_threshold.mem";
                MODE_SOBEL:     expected_mem_path = "generated/test_vectors/sample_000_sobel.mem";
                MODE_CONV3X3:   expected_mem_path = "generated/test_vectors/sample_000_conv.mem";
                MODE_VECTOR4:   expected_mem_path = "generated/test_vectors/sample_000_conv4.mem";
                default:        expected_mem_path = "generated/test_vectors/sample_000_threshold.mem";
            endcase
        end

        $timeformat(-9, 0, " ns");
        $display("AXI4-Stream top input MEM:    %s", input_mem_path);
        $display("AXI4-Stream top expected MEM: %s", expected_mem_path);
        $display("AXI4-Stream top mode:         %0d", preprocess_mode);

        $readmemh(input_mem_path, input_pixels);
        $readmemh(expected_mem_path, expected_words);

        rstn <= 1'b0;
        s_axi_awaddr <= '0;
        s_axi_awprot <= '0;
        s_axi_awvalid <= 1'b0;
        s_axi_wdata <= '0;
        s_axi_wstrb <= '0;
        s_axi_wvalid <= 1'b0;
        s_axi_bready <= 1'b0;
        s_axi_araddr <= '0;
        s_axi_arprot <= '0;
        s_axi_arvalid <= 1'b0;
        s_axi_rready <= 1'b0;
        s_axis_tdata <= '0;
        s_axis_tkeep <= '0;
        s_axis_tvalid <= 1'b0;
        s_axis_tlast <= 1'b0;
        ready_enable <= 1'b0;

        repeat (5) @(posedge clk);
        @(negedge clk);
        rstn <= 1'b1;

        repeat (2) @(posedge clk);
        if (s_axis_tready !== 1'b0) begin
            mismatch_count++;
            $error("S_AXIS_TREADY was high before CTRL.start armed the stream core.");
        end

        check_write_strobes();
        check_axi_response_policy();

        axi_read(ADDR_IP_ID, read_value);
        if (read_value !== 32'h5a42_4156) begin
            mismatch_count++;
            $error("IP_ID mismatch: actual=0x%08h", read_value);
        end
        axi_read(ADDR_IP_VERSION, read_value);
        if (read_value !== 32'h0002_0000) begin
            mismatch_count++;
            $error("IP_VERSION mismatch: actual=0x%08h", read_value);
        end
        axi_read(ADDR_CAPABILITIES, read_value);
        if (read_value !== 32'h000f_044f) begin
            mismatch_count++;
            $error("CAPABILITIES mismatch: actual=0x%08h", read_value);
        end

        axi_write(ADDR_ERROR_STATUS, 32'h0000_0007);
        axi_write(ADDR_INT_STATUS, 32'h0000_0007);
        axi_write(ADDR_PERF_CONTROL, 32'h0000_0001);
        axi_write(ADDR_INT_ENABLE, 32'h0000_0007);
        if (irq !== 1'b0) begin
            mismatch_count++;
            $error("IRQ remained asserted after W1C initialization.");
        end

        axi_read(ADDR_IMAGE_PIXELS, read_value);
        if (read_value !== C_S_AXI_DATA_WIDTH'(IMAGE_PIXELS)) begin
            mismatch_count++;
            $error("IMAGE_PIXELS mismatch: actual=%0d expected=%0d", read_value, IMAGE_PIXELS);
        end

        axi_read(ADDR_PIXELS_PER_CYCLE, read_value);
        if (read_value !== C_S_AXI_DATA_WIDTH'(1)) begin
            mismatch_count++;
            $error("PIXELS_PER_CYCLE mismatch: actual=%0d expected=1", read_value);
        end

        axi_write(ADDR_THRESHOLD, 32'h0000_0011);
        axi_read(ADDR_THRESHOLD, read_value);
        if (read_value[7:0] !== 8'h11) begin
            mismatch_count++;
            $error("first repeated-address threshold read returned %02h", read_value[7:0]);
        end
        axi_write(ADDR_THRESHOLD, 32'h0000_0022);
        axi_read(ADDR_THRESHOLD, read_value);
        if (read_value[7:0] !== 8'h22) begin
            mismatch_count++;
            $error("second repeated-address threshold read returned stale value %02h", read_value[7:0]);
        end

        axi_write(ADDR_THRESHOLD, C_S_AXI_DATA_WIDTH'(128));
        axi_write(ADDR_MODE, C_S_AXI_DATA_WIDTH'(preprocess_mode));

        if (preprocess_mode == MODE_CONV3X3) begin
            axi_write(ADDR_CONV_K00, C_S_AXI_DATA_WIDTH'(-2));
            axi_write(ADDR_CONV_K01, C_S_AXI_DATA_WIDTH'(-1));
            axi_write(ADDR_CONV_K02, C_S_AXI_DATA_WIDTH'(0));
            axi_write(ADDR_CONV_K10, C_S_AXI_DATA_WIDTH'(-1));
            axi_write(ADDR_CONV_K11, C_S_AXI_DATA_WIDTH'(6));
            axi_write(ADDR_CONV_K12, C_S_AXI_DATA_WIDTH'(1));
            axi_write(ADDR_CONV_K20, C_S_AXI_DATA_WIDTH'(0));
            axi_write(ADDR_CONV_K21, C_S_AXI_DATA_WIDTH'(1));
            axi_write(ADDR_CONV_K22, C_S_AXI_DATA_WIDTH'(2));
            axi_write(ADDR_CONV_BIAS, C_S_AXI_DATA_WIDTH'(-128));
            axi_write(ADDR_CONV_SHIFT, C_S_AXI_DATA_WIDTH'(3));
            axi_write(ADDR_CONV_RELU_EN, C_S_AXI_DATA_WIDTH'(1));
        end else if (preprocess_mode == MODE_VECTOR4) begin
            program_vector_config();
        end

        axi_write(ADDR_CTRL, C_S_AXI_DATA_WIDTH'(1));

        axi_write_strb_expect(ADDR_THRESHOLD, 32'd0, 4'hf, 2'b10);
        axi_write_strb_expect(ADDR_CTRL, 32'd1, 4'hf, 2'b10);
        axi_read(ADDR_THRESHOLD, read_value);
        if (read_value[7:0] !== 8'd128) begin
            mismatch_count++;
            $error("busy-time rejected write changed threshold: actual=%0d", read_value[7:0]);
        end

        axi_read(ADDR_ERROR_STATUS, read_value);
        if (!read_value[1] || !irq) begin
            mismatch_count++;
            $error("rejected busy write did not latch bus-error status/IRQ: status=0x%08h irq=%0b", read_value, irq);
        end
        axi_read(ADDR_ERROR_COUNT, read_value);
        if (read_value < 2) begin
            mismatch_count++;
            $error("ERROR_COUNT did not count rejected busy writes: actual=%0d", read_value);
        end
        axi_write(ADDR_ERROR_STATUS, 32'h0000_0007);
        axi_write(ADDR_INT_STATUS, 32'h0000_0007);
        axi_write(ADDR_PERF_CONTROL, 32'h0000_0001);
        if (irq !== 1'b0) begin
            mismatch_count++;
            $error("IRQ did not deassert after INT_STATUS W1C.");
        end

        axi_read(ADDR_STATUS, status_value);
        if (status_value[0] !== 1'b1 || status_value[3] !== 1'b1) begin
            mismatch_count++;
            $error("STATUS did not report busy/armed after start: status=0x%08h", status_value);
        end

        ready_enable <= 1'b1;

        for (int pixel = 0; pixel < IMAGE_PIXELS; pixel++) begin
            send_pixel(pixel);
        end

        wait (output_count == IMAGE_PIXELS);
        repeat (3) @(posedge clk);

        axi_read(ADDR_STATUS, status_value);
        if (status_value[0] !== 1'b0) begin
            mismatch_count++;
            $error("STATUS.busy stayed high after output packet: status=0x%08h", status_value);
        end

        if (status_value[1] !== 1'b1) begin
            mismatch_count++;
            $error("STATUS.done did not latch after output packet: status=0x%08h", status_value);
        end

        if (status_value[2] !== 1'b0) begin
            mismatch_count++;
            $error("STATUS.packet_error asserted for legal packet: status=0x%08h", status_value);
        end

        axi_read(ADDR_PROCESSING_CYCLES, read_value);
        measured_processing_cycles = read_value;
        if (read_value == 0) begin
            mismatch_count++;
            $error("PROCESSING_CYCLES was zero after stream operation.");
        end


        axi_read(ADDR_FRAME_COUNT, read_value);
        if (read_value !== 32'd1) begin
            mismatch_count++;
            $error("FRAME_COUNT mismatch: actual=%0d expected=1", read_value);
        end
        axi_read(ADDR_ERROR_COUNT, read_value);
        if (read_value !== 32'd0) begin
            mismatch_count++;
            $error("ERROR_COUNT changed during legal packet: actual=%0d", read_value);
        end
        axi_read(ADDR_INPUT_STALL_CYCLES, read_value);
        $display("INFO: input stall counter=%0d cycles", read_value);
        axi_read(ADDR_OUTPUT_STALL_CYCLES, read_value);
        if (read_value == 0) begin
            mismatch_count++;
            $error("OUTPUT_STALL_CYCLES did not observe directed backpressure.");
        end
        axi_read(ADDR_INT_STATUS, read_value);
        if (!read_value[0] || !irq) begin
            mismatch_count++;
            $error("frame completion did not latch done interrupt/IRQ: status=0x%08h irq=%0b", read_value, irq);
        end
        axi_write(ADDR_INT_STATUS, 32'h0000_0001);
        if (irq !== 1'b0) begin
            mismatch_count++;
            $error("done IRQ did not clear after W1C.");
        end

        axi_write(ADDR_CTRL, C_S_AXI_DATA_WIDTH'(2));
        axi_read(ADDR_STATUS, status_value);
        if (status_value[1] !== 1'b0) begin
            mismatch_count++;
            $error("STATUS.done did not clear after CTRL.clear_done: status=0x%08h", status_value);
        end

        // Re-arm without resetting the block. This catches one-shot state,
        // stale response data, and counter/interrupt accumulation defects.
        axi_write(ADDR_CTRL, C_S_AXI_DATA_WIDTH'(1));
        axi_read(ADDR_STATUS, status_value);
        if (status_value[0] !== 1'b1 || status_value[3] !== 1'b1) begin
            mismatch_count++;
            $error("second-frame start did not report busy/armed: status=0x%08h", status_value);
        end
        for (int pixel = 0; pixel < IMAGE_PIXELS; pixel++) begin
            send_pixel(pixel);
        end
        wait (output_count == DIRECTED_OUTPUT_PIXELS);
        repeat (3) @(posedge clk);

        axi_read(ADDR_STATUS, status_value);
        if (status_value[3:0] !== 4'b0010) begin
            mismatch_count++;
            $error("second-frame terminal status mismatch: status=0x%08h", status_value);
        end
        axi_read(ADDR_FRAME_COUNT, read_value);
        if (read_value !== C_S_AXI_DATA_WIDTH'(DIRECTED_FRAME_COUNT)) begin
            mismatch_count++;
            $error(
                "FRAME_COUNT after re-arm actual=%0d expected=%0d",
                read_value,
                DIRECTED_FRAME_COUNT
            );
        end
        axi_read(ADDR_PROCESSING_CYCLES, read_value);
        measured_processing_cycles = read_value;
        if (read_value == 0) begin
            mismatch_count++;
            $error("PROCESSING_CYCLES was zero after second stream operation");
        end
        axi_read(ADDR_ERROR_COUNT, read_value);
        if (read_value !== 32'd0) begin
            mismatch_count++;
            $error("ERROR_COUNT changed during second legal packet: actual=%0d", read_value);
        end
        axi_read(ADDR_INT_STATUS, read_value);
        if (!read_value[0] || !irq) begin
            mismatch_count++;
            $error("second completion did not relatch done IRQ: status=0x%08h irq=%0b", read_value, irq);
        end
        axi_write(ADDR_INT_STATUS, 32'h0000_0001);
        if (irq !== 1'b0) begin
            mismatch_count++;
            $error("second done IRQ did not clear after W1C");
        end

        if (mismatch_count == 0) begin
            $display(
                "PASS: AXI4-Stream selectable top mode %0d matched %0d frames x %0d pixels; last frame took %0d cycles.",
                preprocess_mode,
                DIRECTED_FRAME_COUNT,
                IMAGE_PIXELS,
                measured_processing_cycles
            );
            $finish;
        end

        $fatal(1, "FAIL: AXI4-Stream selectable top found %0d issue(s).", mismatch_count);
    end

    initial begin : drive_output_backpressure
        forever begin
            @(posedge clk);

            if (rstn === 1'b0) begin
                m_axis_tready <= 1'b0;
                ready_pattern_count <= 0;
            end else if (ready_enable !== 1'b1) begin
                m_axis_tready <= 1'b0;
                ready_pattern_count <= 0;
            end else if (((ready_pattern_count % 19) == 4) ||
                         ((ready_pattern_count % 37) == 15)) begin
                m_axis_tready <= 1'b0;
                ready_pattern_count <= ready_pattern_count + 1;
            end else begin
                m_axis_tready <= 1'b1;
                ready_pattern_count <= ready_pattern_count + 1;
            end
        end
    end

    initial begin : check_output_stream
        forever begin
            @(posedge clk);

            if (rstn === 1'b0) begin
                output_count <= 0;
            end else if ((m_axis_tvalid === 1'b1) && (m_axis_tready === 1'b1)) begin
                if (output_count >= DIRECTED_OUTPUT_PIXELS) begin
                    mismatch_count++;
                    $error("Received extra output beat %0d.", output_count);
                end else begin
                    if (m_axis_tkeep !== PIXEL_KEEP) begin
                        mismatch_count++;
                        $error(
                            "tkeep mismatch at output %0d: actual=0x%0h expected=0x%0h",
                            output_count,
                            m_axis_tkeep,
                            PIXEL_KEEP
                        );
                    end

                    if ((preprocess_mode != MODE_VECTOR4) &&
                        (m_axis_tdata[C_AXIS_DATA_WIDTH-1:DATA_WIDTH] !== '0)) begin
                        mismatch_count++;
                        $error(
                            "upper tdata bits were nonzero at output %0d: actual=0x%0h",
                            output_count,
                            m_axis_tdata
                        );
                    end

                    if ((preprocess_mode == MODE_VECTOR4) &&
                        (m_axis_tdata !== expected_words[output_count % IMAGE_PIXELS])) begin
                        mismatch_count++;
                        $error(
                            "packed vector mismatch at output %0d: actual=0x%08h expected=0x%08h",
                            output_count,
                            m_axis_tdata,
                            expected_words[output_count % IMAGE_PIXELS]
                        );
                    end else if ((preprocess_mode != MODE_VECTOR4) &&
                                 (m_axis_tdata[DATA_WIDTH-1:0] !==
                                  expected_words[output_count % IMAGE_PIXELS][DATA_WIDTH-1:0])) begin
                        mismatch_count++;
                        $error(
                            "pixel mismatch at output %0d: actual=0x%02h expected=0x%02h",
                            output_count,
                            m_axis_tdata[DATA_WIDTH-1:0],
                            expected_words[output_count % IMAGE_PIXELS][DATA_WIDTH-1:0]
                        );
                    end

                    if (m_axis_tlast !== ((output_count % IMAGE_PIXELS) == IMAGE_PIXELS - 1)) begin
                        mismatch_count++;
                        $error(
                            "tlast mismatch at output %0d: actual=%0b expected=%0b",
                            output_count,
                            m_axis_tlast,
                            ((output_count % IMAGE_PIXELS) == IMAGE_PIXELS - 1)
                        );
                    end
                end

                output_count <= output_count + 1;
            end
        end
    end

    initial begin : check_stall_stability
        was_stalled <= 1'b0;
        held_tdata  <= '0;
        held_tkeep  <= '0;
        held_tlast  <= 1'b0;

        forever begin
            @(posedge clk);

            if (rstn === 1'b0) begin
                was_stalled <= 1'b0;
            end else begin
                if (was_stalled && (m_axis_tvalid === 1'b1) && (m_axis_tready === 1'b0)) begin
                    if ((m_axis_tdata !== held_tdata) ||
                        (m_axis_tkeep !== held_tkeep) ||
                        (m_axis_tlast !== held_tlast)) begin
                        mismatch_count++;
                        $error("AXI4-Stream selectable top output changed while stalled.");
                    end
                end

                if ((m_axis_tvalid === 1'b1) && (m_axis_tready === 1'b0)) begin
                    held_tdata  <= m_axis_tdata;
                    held_tkeep  <= m_axis_tkeep;
                    held_tlast  <= m_axis_tlast;
                    was_stalled <= 1'b1;
                end else begin
                    was_stalled <= 1'b0;
                end
            end
        end
    end

    initial begin : timeout
        repeat (TIMEOUT_CYCLES) @(posedge clk);
        $fatal(1, "FAIL: timeout after %0d cycles.", TIMEOUT_CYCLES);
    end

endmodule

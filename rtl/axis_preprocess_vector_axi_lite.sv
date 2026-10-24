`timescale 1 ns / 100 ps

// Module: axis_preprocess_vector_axi_lite
// Description:
//Selectable stream preprocessor with atomic four-filter learned configuration.

module axis_preprocess_vector_axi_lite #(
    parameter int C_S_AXI_DATA_WIDTH = 32,
    parameter int C_S_AXI_ADDR_WIDTH = 8,
    parameter int C_AXIS_DATA_WIDTH = 32,
    parameter int DATA_WIDTH = 8,
    parameter int IMAGE_WIDTH = 28,
    parameter int IMAGE_HEIGHT = 28,
    parameter int IMAGE_PIXELS = IMAGE_WIDTH * IMAGE_HEIGHT,
    parameter int CYCLE_COUNT_WIDTH = 32
) (
    input  logic                                      S_AXI_ACLK,
    input  logic                                      S_AXI_ARESETN,

    input  logic [C_S_AXI_ADDR_WIDTH-1:0]             S_AXI_AWADDR,
    input  logic [2:0]                                S_AXI_AWPROT,
    input  logic                                      S_AXI_AWVALID,
    output logic                                      S_AXI_AWREADY,

    input  logic [C_S_AXI_DATA_WIDTH-1:0]             S_AXI_WDATA,
    input  logic [(C_S_AXI_DATA_WIDTH/8)-1:0]         S_AXI_WSTRB,
    input  logic                                      S_AXI_WVALID,
    output logic                                      S_AXI_WREADY,

    output logic [1:0]                                S_AXI_BRESP,
    output logic                                      S_AXI_BVALID,
    input  logic                                      S_AXI_BREADY,

    input  logic [C_S_AXI_ADDR_WIDTH-1:0]             S_AXI_ARADDR,
    input  logic [2:0]                                S_AXI_ARPROT,
    input  logic                                      S_AXI_ARVALID,
    output logic                                      S_AXI_ARREADY,

    output logic [C_S_AXI_DATA_WIDTH-1:0]             S_AXI_RDATA,
    output logic [1:0]                                S_AXI_RRESP,
    output logic                                      S_AXI_RVALID,
    input  logic                                      S_AXI_RREADY,

    input  logic [C_AXIS_DATA_WIDTH-1:0]              S_AXIS_TDATA,
    input  logic [(C_AXIS_DATA_WIDTH/8)-1:0]          S_AXIS_TKEEP,
    input  logic                                      S_AXIS_TVALID,
    output logic                                      S_AXIS_TREADY,
    input  logic                                      S_AXIS_TLAST,

    output logic [C_AXIS_DATA_WIDTH-1:0]              M_AXIS_TDATA,
    output logic [(C_AXIS_DATA_WIDTH/8)-1:0]          M_AXIS_TKEEP,
    output logic                                      M_AXIS_TVALID,
    input  logic                                      M_AXIS_TREADY,
    output logic                                      M_AXIS_TLAST,

    output logic                                      irq
);

    localparam int AXI_STRB_WIDTH = C_S_AXI_DATA_WIDTH / 8;
    localparam int AXIS_KEEP_WIDTH = C_AXIS_DATA_WIDTH / 8;
    localparam int VECTOR_FILTERS = 4;
    localparam int VECTOR_TAPS = 9;
    localparam logic [1:0] AXI_RESP_OKAY = 2'b00;
    localparam logic [1:0] AXI_RESP_SLVERR = 2'b10;

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

    localparam logic [31:0] IP_ID_VALUE = 32'h5a42_4156; // "ZBAV"
    localparam logic [31:0] IP_VERSION_VALUE = 32'h0002_0001;
    localparam logic [31:0] CAPABILITIES_VALUE = 32'h000f_044f;

    localparam logic [1:0] MODE_THRESHOLD = 2'd0;
    localparam logic [1:0] MODE_SOBEL     = 2'd1;
    localparam logic [1:0] MODE_CONV3X3   = 2'd2;
    localparam logic [1:0] MODE_VECTOR4   = 2'd3;

    localparam logic signed [7:0] DEFAULT_VECTOR_WEIGHTS [0:VECTOR_FILTERS-1][0:VECTOR_TAPS-1] = '{
        '{29, 104, 127, -115, -76, 58, -78, -92, -114},
        '{13, -13, -116, -49, -79, 15, -127, -26, 11},
        '{48, -11, -127, -111, -76, -35, 39, 126, 94},
        '{-60, -14, 114, -74, 108, 15, 29, 127, 83}
    };
    localparam logic signed [31:0] DEFAULT_VECTOR_BIAS [0:VECTOR_FILTERS-1] =
        '{11029, 17936, 257, -131};
    localparam logic [4:0] DEFAULT_VECTOR_SHIFT [0:VECTOR_FILTERS-1] = '{9, 7, 9, 9};

    logic                                      rst;
    logic                                      aw_captured_r;
    logic                                      w_captured_r;
    logic [C_S_AXI_ADDR_WIDTH-1:0]             awaddr_r;
    logic [C_S_AXI_DATA_WIDTH-1:0]             wdata_r;
    logic [AXI_STRB_WIDTH-1:0]                 wstrb_r;
    logic                                      write_fire;

    logic                                      reg_write_en;
    logic [C_S_AXI_ADDR_WIDTH-1:0]             reg_write_addr;
    logic [C_S_AXI_DATA_WIDTH-1:0]             reg_write_data;
    logic [AXI_STRB_WIDTH-1:0]                 reg_write_strb;
    logic                                      reg_read_en;
    logic [C_S_AXI_ADDR_WIDTH-1:0]             reg_read_addr;

    logic [DATA_WIDTH-1:0]                     threshold_r;
    logic [DATA_WIDTH-1:0]                     active_threshold_r;
    logic [1:0]                                mode_r;
    logic [1:0]                                active_mode_r;
    logic signed [7:0]                         conv_k00_r;
    logic signed [7:0]                         conv_k01_r;
    logic signed [7:0]                         conv_k02_r;
    logic signed [7:0]                         conv_k10_r;
    logic signed [7:0]                         conv_k11_r;
    logic signed [7:0]                         conv_k12_r;
    logic signed [7:0]                         conv_k20_r;
    logic signed [7:0]                         conv_k21_r;
    logic signed [7:0]                         conv_k22_r;
    logic signed [31:0]                        conv_bias_r;
    logic [4:0]                                conv_shift_r;
    logic                                      conv_relu_enable_r;
    logic signed [7:0]                         active_conv_k00_r;
    logic signed [7:0]                         active_conv_k01_r;
    logic signed [7:0]                         active_conv_k02_r;
    logic signed [7:0]                         active_conv_k10_r;
    logic signed [7:0]                         active_conv_k11_r;
    logic signed [7:0]                         active_conv_k12_r;
    logic signed [7:0]                         active_conv_k20_r;
    logic signed [7:0]                         active_conv_k21_r;
    logic signed [7:0]                         active_conv_k22_r;
    logic signed [31:0]                        active_conv_bias_r;
    logic [4:0]                                active_conv_shift_r;
    logic                                      active_conv_relu_enable_r;
    logic                                      armed_r;
    logic                                      done_latched_r;
    logic                                      packet_error_latched_r;
    logic [CYCLE_COUNT_WIDTH-1:0]              processing_cycles_latched_r;
    logic                                      start_pulse;
    logic                                      clear_done_pulse;
    logic                                      abort_pulse;
    logic                                      datapath_resetn;
    logic                                      stream_busy;
    logic                                      vector_commit_pulse;
    logic                                      perf_clear_pulse;
    logic                                      frame_done_event;
    logic                                      packet_error_event;
    logic                                      write_error_event;
    logic                                      read_error_event;
    logic [31:0]                               frame_count_r;
    logic [31:0]                               error_count_r;
    logic [31:0]                               input_stall_cycles_r;
    logic [31:0]                               output_stall_cycles_r;
    logic [2:0]                                error_status_r;
    logic [2:0]                                int_status_r;
    logic [2:0]                                int_enable_r;
    logic [2:0]                                error_clear_mask;
    logic [2:0]                                int_clear_mask;

    logic [5:0]                                vector_cfg_index_r;
    logic [31:0]                               vector_cfg_version_r;
    logic signed [7:0]                         vector_shadow_weights_r [0:VECTOR_FILTERS-1][0:VECTOR_TAPS-1];
    logic signed [31:0]                        vector_shadow_bias_r [0:VECTOR_FILTERS-1];
    logic [4:0]                                vector_shadow_shift_r [0:VECTOR_FILTERS-1];
    logic                                      vector_shadow_relu_r [0:VECTOR_FILTERS-1];
    logic signed [7:0]                         vector_committed_weights_r [0:VECTOR_FILTERS-1][0:VECTOR_TAPS-1];
    logic signed [31:0]                        vector_committed_bias_r [0:VECTOR_FILTERS-1];
    logic [4:0]                                vector_committed_shift_r [0:VECTOR_FILTERS-1];
    logic                                      vector_committed_relu_r [0:VECTOR_FILTERS-1];
    logic signed [7:0]                         active_vector_weights_r [0:VECTOR_FILTERS-1][0:VECTOR_TAPS-1];
    logic signed [31:0]                        active_vector_bias_r [0:VECTOR_FILTERS-1];
    logic [4:0]                                active_vector_shift_r [0:VECTOR_FILTERS-1];
    logic                                      active_vector_relu_r [0:VECTOR_FILTERS-1];

    logic                                      threshold_clear_done;
    logic                                      threshold_busy;
    logic                                      threshold_done;
    logic                                      threshold_packet_error;
    logic [CYCLE_COUNT_WIDTH-1:0]              threshold_cycles;
    logic                                      threshold_s_tvalid;
    logic                                      threshold_s_tready;
    logic [C_AXIS_DATA_WIDTH-1:0]              threshold_m_tdata;
    logic [AXIS_KEEP_WIDTH-1:0]                threshold_m_tkeep;
    logic                                      threshold_m_tvalid;
    logic                                      threshold_m_tready;
    logic                                      threshold_m_tlast;

    logic                                      sobel_clear_done;
    logic                                      sobel_busy;
    logic                                      sobel_done;
    logic                                      sobel_packet_error;
    logic [CYCLE_COUNT_WIDTH-1:0]              sobel_cycles;
    logic                                      sobel_s_tvalid;
    logic                                      sobel_s_tready;
    logic [C_AXIS_DATA_WIDTH-1:0]              sobel_m_tdata;
    logic [AXIS_KEEP_WIDTH-1:0]                sobel_m_tkeep;
    logic                                      sobel_m_tvalid;
    logic                                      sobel_m_tready;
    logic                                      sobel_m_tlast;

    logic                                      conv_clear_done;
    logic                                      conv_busy;
    logic                                      conv_done;
    logic                                      conv_packet_error;
    logic [CYCLE_COUNT_WIDTH-1:0]              conv_cycles;
    logic                                      conv_s_tvalid;
    logic                                      conv_s_tready;
    logic [C_AXIS_DATA_WIDTH-1:0]              conv_m_tdata;
    logic [AXIS_KEEP_WIDTH-1:0]                conv_m_tkeep;
    logic                                      conv_m_tvalid;
    logic                                      conv_m_tready;
    logic                                      conv_m_tlast;

    logic                                      vector_clear_done;
    logic                                      vector_busy;
    logic                                      vector_done;
    logic                                      vector_packet_error;
    logic [CYCLE_COUNT_WIDTH-1:0]              vector_cycles;
    logic                                      vector_s_tvalid;
    logic                                      vector_s_tready;
    logic [C_AXIS_DATA_WIDTH-1:0]              vector_m_tdata;
    logic [AXIS_KEEP_WIDTH-1:0]                vector_m_tkeep;
    logic                                      vector_m_tvalid;
    logic                                      vector_m_tready;
    logic                                      vector_m_tlast;

    assign rst = ~S_AXI_ARESETN;

    assign S_AXI_AWREADY = !aw_captured_r && !S_AXI_BVALID;
    assign S_AXI_WREADY = !w_captured_r && !S_AXI_BVALID;
    assign S_AXI_ARREADY = !S_AXI_RVALID;

    assign write_fire = aw_captured_r && w_captured_r && !S_AXI_BVALID;
    assign reg_read_en = S_AXI_ARVALID && S_AXI_ARREADY;
    assign reg_read_addr = S_AXI_ARADDR;

    assign start_pulse =
        reg_write_en && reg_write_strb[0] &&
        (reg_write_addr == ADDR_CTRL) && reg_write_data[0] &&
        !reg_write_data[2] && !stream_busy;

    assign clear_done_pulse =
        reg_write_en && reg_write_strb[0] &&
        (reg_write_addr == ADDR_CTRL) && reg_write_data[1];

    // Reset only streaming state. Keep AXI responses, coefficients and sticky
    // diagnostic history alive so software can recover without a PL reset.
    assign abort_pulse = reg_write_en && reg_write_strb[0] &&
        (reg_write_addr == ADDR_CTRL) && reg_write_data[2];
    assign datapath_resetn = S_AXI_ARESETN && !abort_pulse;

    assign stream_busy = armed_r;
    assign vector_commit_pulse =
        reg_write_en && reg_write_strb[0] &&
        (reg_write_addr == ADDR_VECTOR_CFG_COMMIT) &&
        reg_write_data[0] && !stream_busy;
    assign perf_clear_pulse =
        reg_write_en && reg_write_strb[0] &&
        (reg_write_addr == ADDR_PERF_CONTROL) && reg_write_data[0];

    assign frame_done_event = armed_r && (
        ((active_mode_r == MODE_THRESHOLD) && threshold_done) ||
        ((active_mode_r == MODE_SOBEL) && sobel_done) ||
        ((active_mode_r == MODE_CONV3X3) && conv_done) ||
        ((active_mode_r == MODE_VECTOR4) && vector_done));

    assign packet_error_event = armed_r && (
        ((active_mode_r == MODE_THRESHOLD) && threshold_done && threshold_packet_error) ||
        ((active_mode_r == MODE_SOBEL) && sobel_done && sobel_packet_error) ||
        ((active_mode_r == MODE_CONV3X3) && conv_done && conv_packet_error) ||
        ((active_mode_r == MODE_VECTOR4) && vector_done && vector_packet_error));

    assign write_error_event =
        write_fire &&
        (write_response(awaddr_r, wdata_r, wstrb_r, stream_busy) == AXI_RESP_SLVERR);
    assign read_error_event =
        reg_read_en && (read_response(reg_read_addr) == AXI_RESP_SLVERR);
    assign error_clear_mask =
        (reg_write_en && reg_write_strb[0] && (reg_write_addr == ADDR_ERROR_STATUS)) ?
        reg_write_data[2:0] : 3'b000;
    assign int_clear_mask =
        (reg_write_en && reg_write_strb[0] && (reg_write_addr == ADDR_INT_STATUS)) ?
        reg_write_data[2:0] : 3'b000;
    assign irq = |(int_status_r & int_enable_r);

    assign threshold_clear_done = clear_done_pulse || start_pulse;
    assign sobel_clear_done = clear_done_pulse || start_pulse;
    assign conv_clear_done = clear_done_pulse || start_pulse;
    assign vector_clear_done = clear_done_pulse || start_pulse;

    assign threshold_s_tvalid =
        armed_r && (active_mode_r == MODE_THRESHOLD) && S_AXIS_TVALID;

    assign sobel_s_tvalid =
        armed_r && (active_mode_r == MODE_SOBEL) && S_AXIS_TVALID;

    assign conv_s_tvalid =
        armed_r && (active_mode_r == MODE_CONV3X3) && S_AXIS_TVALID;

    assign vector_s_tvalid =
        armed_r && (active_mode_r == MODE_VECTOR4) && S_AXIS_TVALID;

    assign S_AXIS_TREADY =
        !armed_r                         ? 1'b0 :
        (active_mode_r == MODE_THRESHOLD) ? threshold_s_tready :
        (active_mode_r == MODE_SOBEL)     ? sobel_s_tready :
        (active_mode_r == MODE_CONV3X3)   ? conv_s_tready :
        (active_mode_r == MODE_VECTOR4)   ? vector_s_tready :
                                            1'b0;

    assign threshold_m_tready =
        armed_r && (active_mode_r == MODE_THRESHOLD) && M_AXIS_TREADY;

    assign sobel_m_tready =
        armed_r && (active_mode_r == MODE_SOBEL) && M_AXIS_TREADY;

    assign conv_m_tready =
        armed_r && (active_mode_r == MODE_CONV3X3) && M_AXIS_TREADY;

    assign vector_m_tready =
        armed_r && (active_mode_r == MODE_VECTOR4) && M_AXIS_TREADY;

    assign M_AXIS_TDATA =
        (armed_r && (active_mode_r == MODE_THRESHOLD)) ? threshold_m_tdata :
        (armed_r && (active_mode_r == MODE_SOBEL))     ? sobel_m_tdata :
        (armed_r && (active_mode_r == MODE_CONV3X3))   ? conv_m_tdata :
        (armed_r && (active_mode_r == MODE_VECTOR4))   ? vector_m_tdata :
                                                          '0;

    assign M_AXIS_TKEEP =
        (armed_r && (active_mode_r == MODE_THRESHOLD)) ? threshold_m_tkeep :
        (armed_r && (active_mode_r == MODE_SOBEL))     ? sobel_m_tkeep :
        (armed_r && (active_mode_r == MODE_CONV3X3))   ? conv_m_tkeep :
        (armed_r && (active_mode_r == MODE_VECTOR4))   ? vector_m_tkeep :
                                                          '0;

    assign M_AXIS_TVALID =
        (armed_r && (active_mode_r == MODE_THRESHOLD)) ? threshold_m_tvalid :
        (armed_r && (active_mode_r == MODE_SOBEL))     ? sobel_m_tvalid :
        (armed_r && (active_mode_r == MODE_CONV3X3))   ? conv_m_tvalid :
        (armed_r && (active_mode_r == MODE_VECTOR4))   ? vector_m_tvalid :
                                                          1'b0;

    assign M_AXIS_TLAST =
        (armed_r && (active_mode_r == MODE_THRESHOLD)) ? threshold_m_tlast :
        (armed_r && (active_mode_r == MODE_SOBEL))     ? sobel_m_tlast :
        (armed_r && (active_mode_r == MODE_CONV3X3))   ? conv_m_tlast :
        (armed_r && (active_mode_r == MODE_VECTOR4))   ? vector_m_tlast :
                                                          1'b0;

    function automatic logic [C_S_AXI_DATA_WIDTH-1:0] read_vector_shadow_data;
        logic [1:0] filter_index;
        logic [3:0] entry_index;
        logic [C_S_AXI_DATA_WIDTH-1:0] value;

        filter_index = vector_cfg_index_r[5:4];
        entry_index = vector_cfg_index_r[3:0];
        value = '0;
        if (entry_index < VECTOR_TAPS) begin
            value = {{(C_S_AXI_DATA_WIDTH-8){vector_shadow_weights_r[filter_index][entry_index][7]}},
                     vector_shadow_weights_r[filter_index][entry_index]};
        end else if (entry_index == 4'd9) begin
            value = vector_shadow_bias_r[filter_index];
        end else if (entry_index == 4'd10) begin
            value[4:0] = vector_shadow_shift_r[filter_index];
            value[8] = vector_shadow_relu_r[filter_index];
        end
        return value;
    endfunction

    function automatic logic [C_S_AXI_DATA_WIDTH-1:0] merge_write_data(
        input logic [C_S_AXI_DATA_WIDTH-1:0] current_value,
        input logic [C_S_AXI_DATA_WIDTH-1:0] data,
        input logic [AXI_STRB_WIDTH-1:0] strobes
    );
        logic [C_S_AXI_DATA_WIDTH-1:0] merged;

        merged = current_value;
        for (int byte_index = 0; byte_index < AXI_STRB_WIDTH; byte_index++) begin
            if (strobes[byte_index]) begin
                merged[byte_index*8 +: 8] = data[byte_index*8 +: 8];
            end
        end

        return merged;
    endfunction

    function automatic logic is_write_address(
        input logic [C_S_AXI_ADDR_WIDTH-1:0] addr
    );
        unique case (addr)
            ADDR_CTRL,
            ADDR_THRESHOLD,
            ADDR_MODE,
            ADDR_CONV_K00,
            ADDR_CONV_K01,
            ADDR_CONV_K02,
            ADDR_CONV_K10,
            ADDR_CONV_K11,
            ADDR_CONV_K12,
            ADDR_CONV_K20,
            ADDR_CONV_K21,
            ADDR_CONV_K22,
            ADDR_CONV_BIAS,
            ADDR_CONV_SHIFT,
            ADDR_CONV_RELU_EN,
            ADDR_VECTOR_CFG_INDEX,
            ADDR_VECTOR_CFG_DATA,
            ADDR_VECTOR_CFG_COMMIT,
            ADDR_ERROR_STATUS,
            ADDR_INT_STATUS,
            ADDR_INT_ENABLE,
            ADDR_PERF_CONTROL: return 1'b1;
            default: return 1'b0;
        endcase
    endfunction

    function automatic logic is_read_address(
        input logic [C_S_AXI_ADDR_WIDTH-1:0] addr
    );
        unique case (addr)
            ADDR_STATUS,
            ADDR_THRESHOLD,
            ADDR_IMAGE_PIXELS,
            ADDR_PIXELS_PER_CYCLE,
            ADDR_PROCESSING_CYCLES,
            ADDR_MODE,
            ADDR_CONV_K00,
            ADDR_CONV_K01,
            ADDR_CONV_K02,
            ADDR_CONV_K10,
            ADDR_CONV_K11,
            ADDR_CONV_K12,
            ADDR_CONV_K20,
            ADDR_CONV_K21,
            ADDR_CONV_K22,
            ADDR_CONV_BIAS,
            ADDR_CONV_SHIFT,
            ADDR_CONV_RELU_EN,
            ADDR_VECTOR_CFG_INDEX,
            ADDR_VECTOR_CFG_DATA,
            ADDR_VECTOR_CFG_VERSION,
            ADDR_IP_ID,
            ADDR_IP_VERSION,
            ADDR_CAPABILITIES,
            ADDR_FRAME_COUNT,
            ADDR_ERROR_COUNT,
            ADDR_INPUT_STALL_CYCLES,
            ADDR_OUTPUT_STALL_CYCLES,
            ADDR_ERROR_STATUS,
            ADDR_INT_STATUS,
            ADDR_INT_ENABLE: return 1'b1;
            default: return 1'b0;
        endcase
    endfunction

    function automatic logic [1:0] write_response(
        input logic [C_S_AXI_ADDR_WIDTH-1:0] addr,
        input logic [C_S_AXI_DATA_WIDTH-1:0] data,
        input logic [AXI_STRB_WIDTH-1:0] strobes,
        input logic busy
    );
        if ((addr[1:0] != 2'b00) || !is_write_address(addr)) begin
            return AXI_RESP_SLVERR;
        end
        if (strobes == '0) begin
            return AXI_RESP_OKAY;
        end
        if (busy) begin
            if (addr == ADDR_CTRL) begin
                return (strobes[0] && data[0]) ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
            end
            if (addr == ADDR_VECTOR_CFG_COMMIT) begin
                return (strobes[0] && data[0]) ? AXI_RESP_SLVERR : AXI_RESP_OKAY;
            end
            if ((addr == ADDR_ERROR_STATUS) ||
                (addr == ADDR_INT_STATUS) ||
                (addr == ADDR_INT_ENABLE) ||
                (addr == ADDR_PERF_CONTROL)) begin
                return AXI_RESP_OKAY;
            end
            return AXI_RESP_SLVERR;
        end
        return AXI_RESP_OKAY;
    endfunction

    function automatic logic [1:0] read_response(
        input logic [C_S_AXI_ADDR_WIDTH-1:0] addr
    );
        if ((addr[1:0] != 2'b00) || !is_read_address(addr)) begin
            return AXI_RESP_SLVERR;
        end
        return AXI_RESP_OKAY;
    endfunction

    function automatic logic [C_S_AXI_DATA_WIDTH-1:0] read_register(
        input logic [C_S_AXI_ADDR_WIDTH-1:0] addr
    );
        logic [C_S_AXI_DATA_WIDTH-1:0] value;

        value = '0;
        unique case (addr)
            ADDR_STATUS : begin
                value[0] = stream_busy;
                value[1] = done_latched_r;
                value[2] = packet_error_latched_r;
                value[3] = armed_r;
            end

            ADDR_THRESHOLD : begin
                value[DATA_WIDTH-1:0] = threshold_r;
            end

            ADDR_IMAGE_PIXELS : begin
                value = C_S_AXI_DATA_WIDTH'(IMAGE_PIXELS);
            end

            ADDR_PIXELS_PER_CYCLE : begin
                value = C_S_AXI_DATA_WIDTH'(1);
            end

            ADDR_PROCESSING_CYCLES : begin
                value[CYCLE_COUNT_WIDTH-1:0] = processing_cycles_latched_r;
            end

            ADDR_MODE : begin
                value[1:0] = mode_r;
            end

            ADDR_CONV_K00 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k00_r[7]}}, conv_k00_r};
            end

            ADDR_CONV_K01 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k01_r[7]}}, conv_k01_r};
            end

            ADDR_CONV_K02 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k02_r[7]}}, conv_k02_r};
            end

            ADDR_CONV_K10 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k10_r[7]}}, conv_k10_r};
            end

            ADDR_CONV_K11 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k11_r[7]}}, conv_k11_r};
            end

            ADDR_CONV_K12 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k12_r[7]}}, conv_k12_r};
            end

            ADDR_CONV_K20 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k20_r[7]}}, conv_k20_r};
            end

            ADDR_CONV_K21 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k21_r[7]}}, conv_k21_r};
            end

            ADDR_CONV_K22 : begin
                value = {{(C_S_AXI_DATA_WIDTH-8){conv_k22_r[7]}}, conv_k22_r};
            end

            ADDR_CONV_BIAS : begin
                value = conv_bias_r;
            end

            ADDR_CONV_SHIFT : begin
                value[4:0] = conv_shift_r;
            end

            ADDR_CONV_RELU_EN : begin
                value[0] = conv_relu_enable_r;
            end

            ADDR_VECTOR_CFG_INDEX : begin
                value[5:0] = vector_cfg_index_r;
            end

            ADDR_VECTOR_CFG_DATA : begin
                value = read_vector_shadow_data();
            end

            ADDR_VECTOR_CFG_VERSION : begin
                value = vector_cfg_version_r;
            end

            ADDR_IP_ID : begin
                value = IP_ID_VALUE;
            end

            ADDR_IP_VERSION : begin
                value = IP_VERSION_VALUE;
            end

            ADDR_CAPABILITIES : begin
                value = CAPABILITIES_VALUE;
            end

            ADDR_FRAME_COUNT : begin
                value = frame_count_r;
            end

            ADDR_ERROR_COUNT : begin
                value = error_count_r;
            end

            ADDR_INPUT_STALL_CYCLES : begin
                value = input_stall_cycles_r;
            end

            ADDR_OUTPUT_STALL_CYCLES : begin
                value = output_stall_cycles_r;
            end

            ADDR_ERROR_STATUS : begin
                value[2:0] = error_status_r;
            end

            ADDR_INT_STATUS : begin
                value[2:0] = int_status_r;
            end

            ADDR_INT_ENABLE : begin
                value[2:0] = int_enable_r;
            end

            default : begin
                value = '0;
            end
        endcase

        return value;
    endfunction

    axis_threshold_preprocess #(
        .DATA_WIDTH(C_AXIS_DATA_WIDTH),
        .KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .PIXEL_WIDTH(DATA_WIDTH),
        .IMAGE_PIXELS(IMAGE_PIXELS),
        .CYCLE_COUNT_WIDTH(CYCLE_COUNT_WIDTH)
    ) threshold_path (
        .aclk(S_AXI_ACLK),
        .aresetn(datapath_resetn),
        .threshold(active_threshold_r),
        .clear_done(threshold_clear_done),
        .busy(threshold_busy),
        .done(threshold_done),
        .packet_error(threshold_packet_error),
        .processing_cycles(threshold_cycles),
        .s_axis_tdata(S_AXIS_TDATA),
        .s_axis_tkeep(S_AXIS_TKEEP),
        .s_axis_tvalid(threshold_s_tvalid),
        .s_axis_tready(threshold_s_tready),
        .s_axis_tlast(S_AXIS_TLAST),
        .m_axis_tdata(threshold_m_tdata),
        .m_axis_tkeep(threshold_m_tkeep),
        .m_axis_tvalid(threshold_m_tvalid),
        .m_axis_tready(threshold_m_tready),
        .m_axis_tlast(threshold_m_tlast)
    );

    axis_sobel_preprocess #(
        .DATA_WIDTH(C_AXIS_DATA_WIDTH),
        .KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .PIXEL_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .CYCLE_COUNT_WIDTH(CYCLE_COUNT_WIDTH)
    ) sobel_path (
        .aclk(S_AXI_ACLK),
        .aresetn(datapath_resetn),
        .clear_done(sobel_clear_done),
        .busy(sobel_busy),
        .done(sobel_done),
        .packet_error(sobel_packet_error),
        .processing_cycles(sobel_cycles),
        .s_axis_tdata(S_AXIS_TDATA),
        .s_axis_tkeep(S_AXIS_TKEEP),
        .s_axis_tvalid(sobel_s_tvalid),
        .s_axis_tready(sobel_s_tready),
        .s_axis_tlast(S_AXIS_TLAST),
        .m_axis_tdata(sobel_m_tdata),
        .m_axis_tkeep(sobel_m_tkeep),
        .m_axis_tvalid(sobel_m_tvalid),
        .m_axis_tready(sobel_m_tready),
        .m_axis_tlast(sobel_m_tlast)
    );

    axis_conv3x3_parallel_preprocess #(
        .DATA_WIDTH(C_AXIS_DATA_WIDTH),
        .KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .PIXEL_WIDTH(DATA_WIDTH),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .CYCLE_COUNT_WIDTH(CYCLE_COUNT_WIDTH)
    ) conv_path (
        .aclk(S_AXI_ACLK),
        .aresetn(datapath_resetn),
        .conv_k00(active_conv_k00_r),
        .conv_k01(active_conv_k01_r),
        .conv_k02(active_conv_k02_r),
        .conv_k10(active_conv_k10_r),
        .conv_k11(active_conv_k11_r),
        .conv_k12(active_conv_k12_r),
        .conv_k20(active_conv_k20_r),
        .conv_k21(active_conv_k21_r),
        .conv_k22(active_conv_k22_r),
        .conv_bias(active_conv_bias_r),
        .conv_shift(active_conv_shift_r),
        .conv_relu_enable(active_conv_relu_enable_r),
        .clear_done(conv_clear_done),
        .busy(conv_busy),
        .done(conv_done),
        .packet_error(conv_packet_error),
        .processing_cycles(conv_cycles),
        .s_axis_tdata(S_AXIS_TDATA),
        .s_axis_tkeep(S_AXIS_TKEEP),
        .s_axis_tvalid(conv_s_tvalid),
        .s_axis_tready(conv_s_tready),
        .s_axis_tlast(S_AXIS_TLAST),
        .m_axis_tdata(conv_m_tdata),
        .m_axis_tkeep(conv_m_tkeep),
        .m_axis_tvalid(conv_m_tvalid),
        .m_axis_tready(conv_m_tready),
        .m_axis_tlast(conv_m_tlast)
    );

    axis_conv3x3_vector4_preprocess #(
        .DATA_WIDTH(C_AXIS_DATA_WIDTH),
        .KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .PIXEL_WIDTH(DATA_WIDTH),
        .FILTERS(VECTOR_FILTERS),
        .TAPS(VECTOR_TAPS),
        .IMAGE_WIDTH(IMAGE_WIDTH),
        .IMAGE_HEIGHT(IMAGE_HEIGHT),
        .CYCLE_COUNT_WIDTH(CYCLE_COUNT_WIDTH)
    ) vector_path (
        .aclk(S_AXI_ACLK),
        .aresetn(datapath_resetn),
        .conv_weights(active_vector_weights_r),
        .conv_bias(active_vector_bias_r),
        .conv_shift(active_vector_shift_r),
        .conv_relu_enable(active_vector_relu_r),
        .clear_done(vector_clear_done),
        .busy(vector_busy),
        .done(vector_done),
        .packet_error(vector_packet_error),
        .processing_cycles(vector_cycles),
        .s_axis_tdata(S_AXIS_TDATA),
        .s_axis_tkeep(S_AXIS_TKEEP),
        .s_axis_tvalid(vector_s_tvalid),
        .s_axis_tready(vector_s_tready),
        .s_axis_tlast(S_AXIS_TLAST),
        .m_axis_tdata(vector_m_tdata),
        .m_axis_tkeep(vector_m_tkeep),
        .m_axis_tvalid(vector_m_tvalid),
        .m_axis_tready(vector_m_tready),
        .m_axis_tlast(vector_m_tlast)
    );

    always_ff @(posedge S_AXI_ACLK) begin
        if (rst) begin
            aw_captured_r <= 1'b0;
            w_captured_r <= 1'b0;
            awaddr_r <= '0;
            wdata_r <= '0;
            wstrb_r <= '0;
            S_AXI_BVALID <= 1'b0;
            S_AXI_BRESP <= AXI_RESP_OKAY;
            reg_write_en <= 1'b0;
            reg_write_addr <= '0;
            reg_write_data <= '0;
            reg_write_strb <= '0;
        end else begin
            reg_write_en <= 1'b0;

            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                aw_captured_r <= 1'b1;
                awaddr_r <= S_AXI_AWADDR;
            end

            if (S_AXI_WVALID && S_AXI_WREADY) begin
                w_captured_r <= 1'b1;
                wdata_r <= S_AXI_WDATA;
                wstrb_r <= S_AXI_WSTRB;
            end

            if (write_fire) begin
                S_AXI_BRESP <= write_response(awaddr_r, wdata_r, wstrb_r, stream_busy);
                reg_write_en <=
                    (write_response(awaddr_r, wdata_r, wstrb_r, stream_busy) == AXI_RESP_OKAY);
                reg_write_addr <= awaddr_r;
                reg_write_data <= wdata_r;
                reg_write_strb <= wstrb_r;
                aw_captured_r <= 1'b0;
                w_captured_r <= 1'b0;
                S_AXI_BVALID <= 1'b1;
            end else if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (rst) begin
            S_AXI_RVALID <= 1'b0;
            S_AXI_RDATA <= '0;
            S_AXI_RRESP <= AXI_RESP_OKAY;
        end else begin
            if (reg_read_en) begin
                S_AXI_RVALID <= 1'b1;
                S_AXI_RRESP <= read_response(reg_read_addr);
                S_AXI_RDATA <=
                    (read_response(reg_read_addr) == AXI_RESP_OKAY) ?
                    read_register(reg_read_addr) : '0;
            end else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (rst) begin
            frame_count_r <= '0;
            error_count_r <= '0;
            input_stall_cycles_r <= '0;
            output_stall_cycles_r <= '0;
            error_status_r <= '0;
            int_status_r <= '0;
            int_enable_r <= '0;
        end else begin
            error_status_r <=
                (error_status_r & ~error_clear_mask) |
                {read_error_event, write_error_event, packet_error_event};
            int_status_r <=
                (int_status_r & ~int_clear_mask) |
                {(write_error_event || read_error_event), packet_error_event, frame_done_event};

            if (reg_write_en && reg_write_strb[0] &&
                (reg_write_addr == ADDR_INT_ENABLE)) begin
                int_enable_r <= reg_write_data[2:0];
            end

            if (perf_clear_pulse) begin
                frame_count_r <= '0;
                error_count_r <= '0;
                input_stall_cycles_r <= '0;
                output_stall_cycles_r <= '0;
            end else begin
                if (frame_done_event && (frame_count_r != 32'hffff_ffff)) begin
                    frame_count_r <= frame_count_r + 32'd1;
                end
                if ((packet_error_event || write_error_event || read_error_event) &&
                    (error_count_r != 32'hffff_ffff)) begin
                    error_count_r <= error_count_r + 32'd1;
                end
                if (stream_busy && S_AXIS_TVALID && !S_AXIS_TREADY &&
                    (input_stall_cycles_r != 32'hffff_ffff)) begin
                    input_stall_cycles_r <= input_stall_cycles_r + 32'd1;
                end
                if (M_AXIS_TVALID && !M_AXIS_TREADY &&
                    (output_stall_cycles_r != 32'hffff_ffff)) begin
                    output_stall_cycles_r <= output_stall_cycles_r + 32'd1;
                end
            end
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (rst) begin
            threshold_r <= DATA_WIDTH'(128);
            active_threshold_r <= DATA_WIDTH'(128);
            mode_r <= MODE_THRESHOLD;
            active_mode_r <= MODE_THRESHOLD;
            conv_k00_r <= -8'sd2;
            conv_k01_r <= -8'sd1;
            conv_k02_r <= 8'sd0;
            conv_k10_r <= -8'sd1;
            conv_k11_r <= 8'sd6;
            conv_k12_r <= 8'sd1;
            conv_k20_r <= 8'sd0;
            conv_k21_r <= 8'sd1;
            conv_k22_r <= 8'sd2;
            conv_bias_r <= -32'sd128;
            conv_shift_r <= 5'd3;
            conv_relu_enable_r <= 1'b1;
            active_conv_k00_r <= -8'sd2;
            active_conv_k01_r <= -8'sd1;
            active_conv_k02_r <= 8'sd0;
            active_conv_k10_r <= -8'sd1;
            active_conv_k11_r <= 8'sd6;
            active_conv_k12_r <= 8'sd1;
            active_conv_k20_r <= 8'sd0;
            active_conv_k21_r <= 8'sd1;
            active_conv_k22_r <= 8'sd2;
            active_conv_bias_r <= -32'sd128;
            active_conv_shift_r <= 5'd3;
            active_conv_relu_enable_r <= 1'b1;
            armed_r <= 1'b0;
            done_latched_r <= 1'b0;
            packet_error_latched_r <= 1'b0;
            processing_cycles_latched_r <= '0;
            vector_cfg_index_r <= '0;
            vector_cfg_version_r <= '0;
            for (int filter_index = 0; filter_index < VECTOR_FILTERS; filter_index++) begin
                vector_shadow_bias_r[filter_index] <= DEFAULT_VECTOR_BIAS[filter_index];
                vector_shadow_shift_r[filter_index] <= DEFAULT_VECTOR_SHIFT[filter_index];
                vector_shadow_relu_r[filter_index] <= 1'b1;
                vector_committed_bias_r[filter_index] <= DEFAULT_VECTOR_BIAS[filter_index];
                vector_committed_shift_r[filter_index] <= DEFAULT_VECTOR_SHIFT[filter_index];
                vector_committed_relu_r[filter_index] <= 1'b1;
                active_vector_bias_r[filter_index] <= DEFAULT_VECTOR_BIAS[filter_index];
                active_vector_shift_r[filter_index] <= DEFAULT_VECTOR_SHIFT[filter_index];
                active_vector_relu_r[filter_index] <= 1'b1;
                for (int tap_index = 0; tap_index < VECTOR_TAPS; tap_index++) begin
                    vector_shadow_weights_r[filter_index][tap_index] <=
                        DEFAULT_VECTOR_WEIGHTS[filter_index][tap_index];
                    vector_committed_weights_r[filter_index][tap_index] <=
                        DEFAULT_VECTOR_WEIGHTS[filter_index][tap_index];
                    active_vector_weights_r[filter_index][tap_index] <=
                        DEFAULT_VECTOR_WEIGHTS[filter_index][tap_index];
                end
            end
        end else begin
            if (clear_done_pulse || start_pulse) begin
                done_latched_r <= 1'b0;
                packet_error_latched_r <= 1'b0;
            end

            if (start_pulse) begin
                armed_r <= 1'b1;
                active_mode_r <= mode_r;
                active_threshold_r <= threshold_r;
                active_conv_k00_r <= conv_k00_r;
                active_conv_k01_r <= conv_k01_r;
                active_conv_k02_r <= conv_k02_r;
                active_conv_k10_r <= conv_k10_r;
                active_conv_k11_r <= conv_k11_r;
                active_conv_k12_r <= conv_k12_r;
                active_conv_k20_r <= conv_k20_r;
                active_conv_k21_r <= conv_k21_r;
                active_conv_k22_r <= conv_k22_r;
                active_conv_bias_r <= conv_bias_r;
                active_conv_shift_r <= conv_shift_r;
                active_conv_relu_enable_r <= conv_relu_enable_r;
                for (int filter_index = 0; filter_index < VECTOR_FILTERS; filter_index++) begin
                    active_vector_bias_r[filter_index] <= vector_committed_bias_r[filter_index];
                    active_vector_shift_r[filter_index] <= vector_committed_shift_r[filter_index];
                    active_vector_relu_r[filter_index] <= vector_committed_relu_r[filter_index];
                    for (int tap_index = 0; tap_index < VECTOR_TAPS; tap_index++) begin
                        active_vector_weights_r[filter_index][tap_index] <=
                            vector_committed_weights_r[filter_index][tap_index];
                    end
                end
            end

            if (armed_r && (active_mode_r == MODE_THRESHOLD) && threshold_done) begin
                armed_r <= 1'b0;
                done_latched_r <= 1'b1;
                packet_error_latched_r <= threshold_packet_error;
                processing_cycles_latched_r <= threshold_cycles;
            end else if (armed_r && (active_mode_r == MODE_SOBEL) && sobel_done) begin
                armed_r <= 1'b0;
                done_latched_r <= 1'b1;
                packet_error_latched_r <= sobel_packet_error;
                processing_cycles_latched_r <= sobel_cycles;
            end else if (armed_r && (active_mode_r == MODE_CONV3X3) && conv_done) begin
                armed_r <= 1'b0;
                done_latched_r <= 1'b1;
                packet_error_latched_r <= conv_packet_error;
                processing_cycles_latched_r <= conv_cycles;
            end else if (armed_r && (active_mode_r == MODE_VECTOR4) && vector_done) begin
                armed_r <= 1'b0;
                done_latched_r <= 1'b1;
                packet_error_latched_r <= vector_packet_error;
                processing_cycles_latched_r <= vector_cycles;
            end

            if (abort_pulse) begin
                armed_r <= 1'b0;
                done_latched_r <= 1'b0;
                packet_error_latched_r <= 1'b0;
                processing_cycles_latched_r <= '0;
            end

            if (vector_commit_pulse) begin
                vector_cfg_version_r <= vector_cfg_version_r + 32'd1;
                for (int filter_index = 0; filter_index < VECTOR_FILTERS; filter_index++) begin
                    vector_committed_bias_r[filter_index] <= vector_shadow_bias_r[filter_index];
                    vector_committed_shift_r[filter_index] <= vector_shadow_shift_r[filter_index];
                    vector_committed_relu_r[filter_index] <= vector_shadow_relu_r[filter_index];
                    for (int tap_index = 0; tap_index < VECTOR_TAPS; tap_index++) begin
                        vector_committed_weights_r[filter_index][tap_index] <=
                            vector_shadow_weights_r[filter_index][tap_index];
                    end
                end
            end

            if (reg_write_en && !stream_busy) begin
                unique case (reg_write_addr)
                    ADDR_THRESHOLD : begin
                        if (reg_write_strb[0]) begin
                            threshold_r <= reg_write_data[DATA_WIDTH-1:0];
                        end
                    end

                    ADDR_MODE : begin
                        if (reg_write_strb[0]) begin
                            unique case (reg_write_data[1:0])
                                MODE_THRESHOLD,
                                MODE_SOBEL,
                                MODE_CONV3X3,
                                MODE_VECTOR4 : begin
                                    mode_r <= reg_write_data[1:0];
                                end

                                default : begin
                                    mode_r <= MODE_THRESHOLD;
                                end
                            endcase
                        end
                    end

                    ADDR_CONV_K00 : begin
                        if (reg_write_strb[0]) conv_k00_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K01 : begin
                        if (reg_write_strb[0]) conv_k01_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K02 : begin
                        if (reg_write_strb[0]) conv_k02_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K10 : begin
                        if (reg_write_strb[0]) conv_k10_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K11 : begin
                        if (reg_write_strb[0]) conv_k11_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K12 : begin
                        if (reg_write_strb[0]) conv_k12_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K20 : begin
                        if (reg_write_strb[0]) conv_k20_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K21 : begin
                        if (reg_write_strb[0]) conv_k21_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_K22 : begin
                        if (reg_write_strb[0]) conv_k22_r <= reg_write_data[7:0];
                    end

                    ADDR_CONV_BIAS : begin
                        conv_bias_r <= merge_write_data(
                            conv_bias_r,
                            reg_write_data,
                            reg_write_strb
                        );
                    end

                    ADDR_CONV_SHIFT : begin
                        if (reg_write_strb[0]) conv_shift_r <= reg_write_data[4:0];
                    end

                    ADDR_CONV_RELU_EN : begin
                        if (reg_write_strb[0]) conv_relu_enable_r <= reg_write_data[0];
                    end

                    ADDR_VECTOR_CFG_INDEX : begin
                        if (reg_write_strb[0]) vector_cfg_index_r <= reg_write_data[5:0];
                    end

                    ADDR_VECTOR_CFG_DATA : begin
                        if (vector_cfg_index_r[3:0] < VECTOR_TAPS) begin
                            if (reg_write_strb[0]) begin
                                vector_shadow_weights_r
                                    [vector_cfg_index_r[5:4]]
                                    [vector_cfg_index_r[3:0]] <= reg_write_data[7:0];
                            end
                        end else if (vector_cfg_index_r[3:0] == 4'd9) begin
                            vector_shadow_bias_r[vector_cfg_index_r[5:4]] <= merge_write_data(
                                vector_shadow_bias_r[vector_cfg_index_r[5:4]],
                                reg_write_data,
                                reg_write_strb
                            );
                        end else if (vector_cfg_index_r[3:0] == 4'd10) begin
                            if (reg_write_strb[0]) begin
                                vector_shadow_shift_r[vector_cfg_index_r[5:4]] <=
                                    reg_write_data[4:0];
                            end
                            if (reg_write_strb[1]) begin
                                vector_shadow_relu_r[vector_cfg_index_r[5:4]] <=
                                    reg_write_data[8];
                            end
                        end
                    end

                    default : begin
                    end
                endcase
            end
        end
    end

    // Mark protection fields as intentionally unused.
    logic unused_axi_prot;
    logic unused_core_status;
    assign unused_axi_prot = ^{S_AXI_AWPROT, S_AXI_ARPROT};
    assign unused_core_status = ^{threshold_busy, sobel_busy, conv_busy, vector_busy};

endmodule


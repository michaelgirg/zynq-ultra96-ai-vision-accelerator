module rv32_axi_lite_master (
    input logic clk,
    input logic rst,

    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [31:0] req_addr,
    input  logic [31:0] req_wdata,
    input  logic [3:0]  req_wstrb,

    output logic        resp_valid,
    input  logic        resp_ready,
    output logic [31:0] resp_rdata,
    output logic        resp_fault,

    output logic [31:0] M_AXI_AWADDR,
    output logic [2:0]  M_AXI_AWPROT,
    output logic        M_AXI_AWVALID,
    input  logic        M_AXI_AWREADY,

    output logic [31:0] M_AXI_WDATA,
    output logic [3:0]  M_AXI_WSTRB,
    output logic        M_AXI_WVALID,
    input  logic        M_AXI_WREADY,

    input  logic [1:0]  M_AXI_BRESP,
    input  logic        M_AXI_BVALID,
    output logic        M_AXI_BREADY,

    output logic [31:0] M_AXI_ARADDR,
    output logic [2:0]  M_AXI_ARPROT,
    output logic        M_AXI_ARVALID,
    input  logic        M_AXI_ARREADY,

    input  logic [31:0] M_AXI_RDATA,
    input  logic [1:0]  M_AXI_RRESP,
    input  logic        M_AXI_RVALID,
    output logic        M_AXI_RREADY
);

    typedef enum logic [2:0] {
        AXI_IDLE,
        AXI_WRITE_CHANNELS,
        AXI_WRITE_RESPONSE,
        AXI_READ_ADDRESS,
        AXI_READ_RESPONSE,
        AXI_PROCESSOR_RESPONSE
    } axi_state_t;

    axi_state_t state;

    logic [31:0] request_addr;
    logic [31:0] request_wdata;
    logic [3:0]  request_wstrb;
    logic        write_address_done;
    logic        write_data_done;
    logic [31:0] response_rdata;
    logic        response_fault;

    assign req_ready = (state == AXI_IDLE);

    assign M_AXI_AWADDR = request_addr;
    assign M_AXI_AWPROT = 3'b000;
    assign M_AXI_AWVALID = (state == AXI_WRITE_CHANNELS) &&
                           !write_address_done;

    assign M_AXI_WDATA = request_wdata;
    assign M_AXI_WSTRB = request_wstrb;
    assign M_AXI_WVALID = (state == AXI_WRITE_CHANNELS) &&
                          !write_data_done;

    assign M_AXI_BREADY = (state == AXI_WRITE_RESPONSE);

    assign M_AXI_ARADDR = request_addr;
    assign M_AXI_ARPROT = 3'b000;
    assign M_AXI_ARVALID = (state == AXI_READ_ADDRESS);

    assign M_AXI_RREADY = (state == AXI_READ_RESPONSE);

    assign resp_valid = (state == AXI_PROCESSOR_RESPONSE);
    assign resp_rdata = response_rdata;
    assign resp_fault = response_fault;

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= AXI_IDLE;
            request_addr <= '0;
            request_wdata <= '0;
            request_wstrb <= '0;
            write_address_done <= 1'b0;
            write_data_done <= 1'b0;
            response_rdata <= '0;
            response_fault <= 1'b0;
        end
        else begin
            case (state)
                AXI_IDLE: begin
                    if (req_valid && req_ready) begin
                        request_addr <= req_addr;
                        request_wdata <= req_wdata;
                        request_wstrb <= req_wstrb;
                        write_address_done <= 1'b0;
                        write_data_done <= 1'b0;
                        response_rdata <= '0;
                        response_fault <= 1'b0;
                        state <= req_write ? AXI_WRITE_CHANNELS :
                                             AXI_READ_ADDRESS;
                    end
                end

                AXI_WRITE_CHANNELS: begin
                    if (M_AXI_AWVALID && M_AXI_AWREADY)
                        write_address_done <= 1'b1;
                    if (M_AXI_WVALID && M_AXI_WREADY)
                        write_data_done <= 1'b1;

                    if ((write_address_done ||
                         (M_AXI_AWVALID && M_AXI_AWREADY)) &&
                        (write_data_done ||
                         (M_AXI_WVALID && M_AXI_WREADY)))
                        state <= AXI_WRITE_RESPONSE;
                end

                AXI_WRITE_RESPONSE: begin
                    if (M_AXI_BVALID && M_AXI_BREADY) begin
                        response_rdata <= '0;
                        response_fault <= (M_AXI_BRESP != 2'b00);
                        state <= AXI_PROCESSOR_RESPONSE;
                    end
                end

                AXI_READ_ADDRESS: begin
                    if (M_AXI_ARVALID && M_AXI_ARREADY)
                        state <= AXI_READ_RESPONSE;
                end

                AXI_READ_RESPONSE: begin
                    if (M_AXI_RVALID && M_AXI_RREADY) begin
                        response_rdata <= M_AXI_RDATA;
                        response_fault <= (M_AXI_RRESP != 2'b00);
                        state <= AXI_PROCESSOR_RESPONSE;
                    end
                end

                AXI_PROCESSOR_RESPONSE: begin
                    if (resp_valid && resp_ready)
                        state <= AXI_IDLE;
                end

                default: state <= AXI_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    property p_aw_stable;
        @(posedge clk) disable iff (rst)
            M_AXI_AWVALID && !M_AXI_AWREADY |=>
                M_AXI_AWVALID && $stable({M_AXI_AWADDR, M_AXI_AWPROT});
    endproperty

    property p_w_stable;
        @(posedge clk) disable iff (rst)
            M_AXI_WVALID && !M_AXI_WREADY |=>
                M_AXI_WVALID && $stable({M_AXI_WDATA, M_AXI_WSTRB});
    endproperty

    property p_ar_stable;
        @(posedge clk) disable iff (rst)
            M_AXI_ARVALID && !M_AXI_ARREADY |=>
                M_AXI_ARVALID && $stable({M_AXI_ARADDR, M_AXI_ARPROT});
    endproperty

    property p_processor_response_stable;
        @(posedge clk) disable iff (rst)
            resp_valid && !resp_ready |=>
                resp_valid && $stable({resp_rdata, resp_fault});
    endproperty

    property p_no_read_write_overlap;
        @(posedge clk) disable iff (rst)
            !(M_AXI_ARVALID && (M_AXI_AWVALID || M_AXI_WVALID));
    endproperty

    assert property (p_aw_stable);
    assert property (p_w_stable);
    assert property (p_ar_stable);
    assert property (p_processor_response_stable);
    assert property (p_no_read_write_overlap);
`endif

endmodule

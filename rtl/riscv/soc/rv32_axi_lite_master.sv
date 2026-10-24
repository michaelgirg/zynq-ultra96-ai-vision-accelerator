module rv32_axi_lite_master #(
    parameter int WATCHDOG_CYCLES = 1000000
) (
    input logic clk,
    // rst is a coordinated fabric reset, NOT the software CPU reset.
    input logic rst,
    input logic processor_reset,
    output logic watchdog_timeout,
    output logic quarantined,
    output logic [31:0] watchdog_addr,
    output logic [31:0] watchdog_info,
    output logic [31:0] watchdog_wait,

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
    logic        request_write;
    logic        processor_abandoned;
    localparam int WAIT_WIDTH = (WATCHDOG_CYCLES > 1) ? $clog2(WATCHDOG_CYCLES) : 1;
    logic [WAIT_WIDTH-1:0] wait_count;
    wire bus_waiting = (state == AXI_WRITE_CHANNELS) || (state == AXI_WRITE_RESPONSE) ||
                       (state == AXI_READ_ADDRESS) || (state == AXI_READ_RESPONSE);
    wire bus_progress = (M_AXI_AWVALID && M_AXI_AWREADY) ||
                        (M_AXI_WVALID && M_AXI_WREADY) ||
                        (M_AXI_BVALID && M_AXI_BREADY) ||
                        (M_AXI_ARVALID && M_AXI_ARREADY) ||
                        (M_AXI_RVALID && M_AXI_RREADY);
    wire [4:0] waiting_channels = {M_AXI_RREADY, M_AXI_ARVALID, M_AXI_BREADY,
                                   M_AXI_WVALID, M_AXI_AWVALID};

    assign req_ready = (state == AXI_IDLE) && !quarantined && !processor_reset;

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

    assign resp_valid = (state == AXI_PROCESSOR_RESPONSE) &&
                        !processor_abandoned && !processor_reset;
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
            request_write <= 1'b0;
            processor_abandoned <= 1'b0;
            wait_count <= '0;
            watchdog_timeout <= 1'b0;
            quarantined <= 1'b0;
            watchdog_addr <= '0;
            watchdog_info <= '0;
            watchdog_wait <= '0;
        end
        else begin
            // Never withdraw AXI VALID or manufacture a bus response on timeout.
            // Preserve/drain this transaction, then block all subsequent traffic.
            if (!bus_waiting || bus_progress) wait_count <= '0;
            else if (!watchdog_timeout) begin
                if (wait_count == WAIT_WIDTH'(WATCHDOG_CYCLES - 1)) begin
                    watchdog_timeout <= 1'b1;
                    quarantined <= 1'b1;
                    watchdog_addr <= request_addr;
                    watchdog_info <= {23'b0, request_write, 3'b0, waiting_channels};
                    watchdog_wait <= WATCHDOG_CYCLES;
                end else wait_count <= wait_count + 1'b1;
            end
            // Software reset must not cancel a partially accepted AXI transfer
            // or let its late response escape into a newly booted processor.
            if (processor_reset && state != AXI_IDLE) begin
                processor_abandoned <= 1'b1;
                quarantined <= 1'b1;
            end
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
                        request_write <= req_write;
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
                        response_fault <= (M_AXI_BRESP != 2'b00) || watchdog_timeout;
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
                        response_fault <= (M_AXI_RRESP != 2'b00) || watchdog_timeout;
                        state <= AXI_PROCESSOR_RESPONSE;
                    end
                end

                AXI_PROCESSOR_RESPONSE: begin
                    if ((resp_valid && resp_ready) || processor_abandoned)
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
        @(posedge clk) disable iff (rst || processor_reset)
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
    assert property (@(posedge clk) disable iff (rst)
        watchdog_timeout |=> watchdog_timeout && quarantined &&
            $stable({watchdog_addr, watchdog_info, watchdog_wait}));
    assert property (@(posedge clk) disable iff (rst)
        quarantined |-> !req_ready);
    assert property (@(posedge clk) disable iff (rst)
        watchdog_timeout && bus_waiting |-> !resp_valid);
`endif

endmodule

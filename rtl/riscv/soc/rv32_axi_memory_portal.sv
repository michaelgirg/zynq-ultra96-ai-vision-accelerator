module rv32_axi_memory_portal #(
    parameter int C_S_AXI_ADDR_WIDTH = 16
) (
    input  logic                          S_AXI_ACLK,
    input  logic                          S_AXI_ARESETN,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_AWADDR,
    input  logic [2:0]                    S_AXI_AWPROT,
    input  logic                          S_AXI_AWVALID,
    output logic                          S_AXI_AWREADY,
    input  logic [31:0]                   S_AXI_WDATA,
    input  logic [3:0]                    S_AXI_WSTRB,
    input  logic                          S_AXI_WVALID,
    output logic                          S_AXI_WREADY,
    output logic [1:0]                    S_AXI_BRESP,
    output logic                          S_AXI_BVALID,
    input  logic                          S_AXI_BREADY,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0] S_AXI_ARADDR,
    input  logic [2:0]                    S_AXI_ARPROT,
    input  logic                          S_AXI_ARVALID,
    output logic                          S_AXI_ARREADY,
    output logic [31:0]                   S_AXI_RDATA,
    output logic [1:0]                    S_AXI_RRESP,
    output logic                          S_AXI_RVALID,
    input  logic                          S_AXI_RREADY,

    output logic        mem_req_valid,
    input  logic        mem_req_ready,
    output logic        mem_req_write,
    output logic [31:0] mem_req_addr,
    output logic [31:0] mem_req_wdata,
    output logic [3:0]  mem_req_wstrb,
    input  logic        mem_resp_valid,
    output logic        mem_resp_ready,
    input  logic [31:0] mem_resp_rdata,
    input  logic        mem_resp_fault
);
    typedef enum logic [1:0] {
        PORTAL_IDLE,
        PORTAL_MEMORY_REQUEST,
        PORTAL_MEMORY_RESPONSE,
        PORTAL_AXI_RESPONSE
    } portal_state_t;

    portal_state_t state;
    logic aw_captured;
    logic [C_S_AXI_ADDR_WIDTH-1:0] awaddr;
    logic w_captured;
    logic [31:0] wdata;
    logic [3:0] wstrb;
    logic request_write;
    logic [C_S_AXI_ADDR_WIDTH-1:0] request_addr;
    logic [31:0] request_wdata;
    logic [3:0] request_wstrb;

    assign S_AXI_AWREADY = (state == PORTAL_IDLE) && !aw_captured;
    assign S_AXI_WREADY = (state == PORTAL_IDLE) && !w_captured;
    assign S_AXI_ARREADY = (state == PORTAL_IDLE) &&
                           !aw_captured && !w_captured &&
                           !S_AXI_AWVALID && !S_AXI_WVALID;

    assign mem_req_valid = (state == PORTAL_MEMORY_REQUEST);
    assign mem_req_write = request_write;
    assign mem_req_addr = {{(32-C_S_AXI_ADDR_WIDTH){1'b0}}, request_addr};
    assign mem_req_wdata = request_wdata;
    assign mem_req_wstrb = request_wstrb;
    assign mem_resp_ready = (state == PORTAL_MEMORY_RESPONSE);

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            state <= PORTAL_IDLE;
            aw_captured <= 1'b0;
            awaddr <= '0;
            w_captured <= 1'b0;
            wdata <= '0;
            wstrb <= '0;
            request_write <= 1'b0;
            request_addr <= '0;
            request_wdata <= '0;
            request_wstrb <= '0;
            S_AXI_BRESP <= 2'b00;
            S_AXI_BVALID <= 1'b0;
            S_AXI_RDATA <= '0;
            S_AXI_RRESP <= 2'b00;
            S_AXI_RVALID <= 1'b0;
        end
        else begin
            case (state)
                PORTAL_IDLE: begin
                    if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                        aw_captured <= 1'b1;
                        awaddr <= S_AXI_AWADDR;
                    end
                    if (S_AXI_WVALID && S_AXI_WREADY) begin
                        w_captured <= 1'b1;
                        wdata <= S_AXI_WDATA;
                        wstrb <= S_AXI_WSTRB;
                    end

                    if (aw_captured && w_captured) begin
                        request_write <= 1'b1;
                        request_addr <= awaddr;
                        request_wdata <= wdata;
                        request_wstrb <= wstrb;
                        aw_captured <= 1'b0;
                        w_captured <= 1'b0;
                        state <= PORTAL_MEMORY_REQUEST;
                    end
                    else if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                        request_write <= 1'b0;
                        request_addr <= S_AXI_ARADDR;
                        request_wdata <= '0;
                        request_wstrb <= '0;
                        state <= PORTAL_MEMORY_REQUEST;
                    end
                end

                PORTAL_MEMORY_REQUEST: begin
                    if (mem_req_valid && mem_req_ready)
                        state <= PORTAL_MEMORY_RESPONSE;
                end

                PORTAL_MEMORY_RESPONSE: begin
                    if (mem_resp_valid && mem_resp_ready) begin
                        if (request_write) begin
                            S_AXI_BRESP <= mem_resp_fault ? 2'b10 : 2'b00;
                            S_AXI_BVALID <= 1'b1;
                        end
                        else begin
                            S_AXI_RDATA <= mem_resp_rdata;
                            S_AXI_RRESP <= mem_resp_fault ? 2'b10 : 2'b00;
                            S_AXI_RVALID <= 1'b1;
                        end
                        state <= PORTAL_AXI_RESPONSE;
                    end
                end

                PORTAL_AXI_RESPONSE: begin
                    if (request_write && S_AXI_BVALID && S_AXI_BREADY) begin
                        S_AXI_BVALID <= 1'b0;
                        state <= PORTAL_IDLE;
                    end
                    else if (!request_write && S_AXI_RVALID && S_AXI_RREADY) begin
                        S_AXI_RVALID <= 1'b0;
                        state <= PORTAL_IDLE;
                    end
                end

                default: state <= PORTAL_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    property p_memory_request_stable;
        @(posedge S_AXI_ACLK) disable iff (!S_AXI_ARESETN)
            mem_req_valid && !mem_req_ready |=>
                mem_req_valid &&
                $stable({mem_req_write, mem_req_addr, mem_req_wdata, mem_req_wstrb});
    endproperty

    property p_read_response_stable;
        @(posedge S_AXI_ACLK) disable iff (!S_AXI_ARESETN)
            S_AXI_RVALID && !S_AXI_RREADY |=>
                S_AXI_RVALID && $stable({S_AXI_RDATA, S_AXI_RRESP});
    endproperty

    property p_write_response_stable;
        @(posedge S_AXI_ACLK) disable iff (!S_AXI_ARESETN)
            S_AXI_BVALID && !S_AXI_BREADY |=>
                S_AXI_BVALID && $stable(S_AXI_BRESP);
    endproperty

    assert property (p_memory_request_stable);
    assert property (p_read_response_stable);
    assert property (p_write_response_stable);
`endif

    logic unused_prot;
    assign unused_prot = ^{S_AXI_AWPROT, S_AXI_ARPROT};
endmodule

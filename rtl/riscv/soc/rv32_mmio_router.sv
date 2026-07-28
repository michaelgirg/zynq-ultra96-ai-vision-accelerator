module rv32_mmio_router
    import soc_address_map_pkg::*;
(
    input logic clk,
    input logic rst,

    input  logic        cpu_req_valid,
    output logic        cpu_req_ready,
    input  logic        cpu_req_write,
    input  logic [31:0] cpu_req_addr,
    input  logic [31:0] cpu_req_wdata,
    input  logic [2:0]  cpu_req_funct3,

    output logic        cpu_resp_valid,
    input  logic        cpu_resp_ready,
    output logic [31:0] cpu_resp_rdata,
    output logic        cpu_resp_fault,

    output logic        local_req_valid,
    input  logic        local_req_ready,
    output logic        local_req_write,
    output logic [31:0] local_req_addr,
    output logic [31:0] local_req_wdata,
    output logic [2:0]  local_req_funct3,

    input  logic        local_resp_valid,
    output logic        local_resp_ready,
    input  logic [31:0] local_resp_rdata,
    input  logic        local_resp_fault,

    output logic        mmio_req_valid,
    input  logic        mmio_req_ready,
    output logic        mmio_req_write,
    output logic [31:0] mmio_req_addr,
    output logic [31:0] mmio_req_wdata,
    output logic [3:0]  mmio_req_wstrb,

    input  logic        mmio_resp_valid,
    output logic        mmio_resp_ready,
    input  logic [31:0] mmio_resp_rdata,
    input  logic        mmio_resp_fault
);

    typedef enum logic [1:0] {
        ROUTER_IDLE,
        ROUTER_WAIT_LOCAL,
        ROUTER_WAIT_MMIO,
        ROUTER_FAULT_RESPONSE
    } router_state_t;

    router_state_t state;

    logic request_is_local;
    logic request_is_mmio;
    logic request_is_word;
    logic request_is_aligned;
    logic request_is_valid_mmio;

    assign request_is_local = is_local_data_address(cpu_req_addr);
    assign request_is_mmio = is_rv_mmio_address(cpu_req_addr);
    assign request_is_word = (cpu_req_funct3 == 3'b010);
    assign request_is_aligned = (cpu_req_addr[1:0] == 2'b00);
    assign request_is_valid_mmio = request_is_mmio &&
                                   request_is_word &&
                                   request_is_aligned;

    always_comb begin
        cpu_req_ready = 1'b0;
        cpu_resp_valid = 1'b0;
        cpu_resp_rdata = '0;
        cpu_resp_fault = 1'b0;

        local_req_valid = 1'b0;
        local_req_write = cpu_req_write;
        local_req_addr = cpu_req_addr;
        local_req_wdata = cpu_req_wdata;
        local_req_funct3 = cpu_req_funct3;
        local_resp_ready = 1'b0;

        mmio_req_valid = 1'b0;
        mmio_req_write = cpu_req_write;
        mmio_req_addr = cpu_req_addr;
        mmio_req_wdata = cpu_req_wdata;
        mmio_req_wstrb = 4'b1111;
        mmio_resp_ready = 1'b0;

        case (state)
            ROUTER_IDLE: begin
                if (request_is_local) begin
                    local_req_valid = cpu_req_valid;
                    cpu_req_ready = local_req_ready;
                end
                else if (request_is_valid_mmio) begin
                    mmio_req_valid = cpu_req_valid;
                    cpu_req_ready = mmio_req_ready;
                end
                else begin
                    // Unmapped and unsupported MMIO operations are accepted
                    // into a local fault response without touching a target.
                    cpu_req_ready = 1'b1;
                end
            end

            ROUTER_WAIT_LOCAL: begin
                cpu_resp_valid = local_resp_valid;
                cpu_resp_rdata = local_resp_rdata;
                cpu_resp_fault = local_resp_fault;
                local_resp_ready = cpu_resp_ready;
            end

            ROUTER_WAIT_MMIO: begin
                cpu_resp_valid = mmio_resp_valid;
                cpu_resp_rdata = mmio_resp_rdata;
                cpu_resp_fault = mmio_resp_fault;
                mmio_resp_ready = cpu_resp_ready;
            end

            ROUTER_FAULT_RESPONSE: begin
                cpu_resp_valid = 1'b1;
                cpu_resp_rdata = '0;
                cpu_resp_fault = 1'b1;
            end

            default: begin
                cpu_req_ready = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= ROUTER_IDLE;
        end
        else begin
            case (state)
                ROUTER_IDLE: begin
                    if (cpu_req_valid && cpu_req_ready) begin
                        if (request_is_local)
                            state <= ROUTER_WAIT_LOCAL;
                        else if (request_is_valid_mmio)
                            state <= ROUTER_WAIT_MMIO;
                        else
                            state <= ROUTER_FAULT_RESPONSE;
                    end
                end

                ROUTER_WAIT_LOCAL: begin
                    if (local_resp_valid && local_resp_ready)
                        state <= ROUTER_IDLE;
                end

                ROUTER_WAIT_MMIO: begin
                    if (mmio_resp_valid && mmio_resp_ready)
                        state <= ROUTER_IDLE;
                end

                ROUTER_FAULT_RESPONSE: begin
                    if (cpu_resp_valid && cpu_resp_ready)
                        state <= ROUTER_IDLE;
                end

                default: state <= ROUTER_IDLE;
            endcase
        end
    end

`ifndef SYNTHESIS
    property p_one_destination;
        @(posedge clk) disable iff (rst)
            !(local_req_valid && mmio_req_valid);
    endproperty

    property p_local_request_stable;
        @(posedge clk) disable iff (rst)
            local_req_valid && !local_req_ready |=>
                local_req_valid &&
                $stable({local_req_write, local_req_addr,
                         local_req_wdata, local_req_funct3});
    endproperty

    property p_mmio_request_stable;
        @(posedge clk) disable iff (rst)
            mmio_req_valid && !mmio_req_ready |=>
                mmio_req_valid &&
                $stable({mmio_req_write, mmio_req_addr,
                         mmio_req_wdata, mmio_req_wstrb});
    endproperty

    property p_response_stable;
        @(posedge clk) disable iff (rst)
            cpu_resp_valid && !cpu_resp_ready |=>
                cpu_resp_valid &&
                $stable({cpu_resp_rdata, cpu_resp_fault});
    endproperty

    assert property (p_one_destination);
    assert property (p_local_request_stable);
    assert property (p_mmio_request_stable);
    assert property (p_response_stable);
`endif

endmodule

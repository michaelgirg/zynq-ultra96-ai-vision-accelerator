// Test-only AXI-Lite wiring. The fabric models arbitration, not AMD SmartConnect.
package soc_sim_bus_pkg;
    typedef struct packed {
        logic [31:0] awaddr;
        logic [2:0] awprot;
        logic awvalid;
        logic [31:0] wdata;
        logic [3:0] wstrb;
        logic wvalid;
        logic bready;
        logic [31:0] araddr;
        logic [2:0] arprot;
        logic arvalid;
        logic rready;
    } request_t;
    typedef struct packed {
        logic awready, wready;
        logic [1:0] bresp;
        logic bvalid, arready;
        logic [31:0] rdata;
        logic [1:0] rresp;
        logic rvalid;
    } response_t;
endpackage

module soc_sim_fabric (
    input logic clk, rst,
    input wire soc_sim_bus_pkg::request_t cpu, host,
    output soc_sim_bus_pkg::response_t cpu_response, host_response,
    output soc_sim_bus_pkg::request_t target [5],
    input wire soc_sim_bus_pkg::response_t response [5]
);
    import soc_sim_bus_pkg::*;
    typedef enum {IDLE, WRITE, READ} state_t;
    state_t state;
    bit owner, last_owner;
    int selected;
    logic aw_done, w_done;
    request_t source;
    response_t result;
    function automatic int decode(input logic [31:0] addr);
        case (addr[31:16])
            16'hA000: return 0; // real accelerator CDC
            16'hA001: return 1; // behavioral simple DMA
            16'hA002: return 2; // real mailbox
            16'hA003: return 3; // real IMEM portal
            16'hA004: return 4; // real DMEM portal
            default: $fatal(1, "unmapped simulation address %h", addr);
        endcase
    endfunction
    always_comb begin
        source = owner ? host : cpu;
        for (int i = 0; i < 5; i++) target[i] = '0;
        result = '0;
        if (state == WRITE) begin
            target[selected] = source;
            target[selected].arvalid = 0;
            target[selected].rready = 0;
            target[selected].awvalid = source.awvalid && !aw_done;
            target[selected].wvalid = source.wvalid && !w_done;
            result.awready = response[selected].awready && !aw_done;
            result.wready = response[selected].wready && !w_done;
            result.bvalid = response[selected].bvalid;
            result.bresp = response[selected].bresp;
        end else if (state == READ) begin
            target[selected] = source;
            target[selected].awvalid = 0;
            target[selected].wvalid = 0;
            target[selected].bready = 0;
            result.arready = response[selected].arready;
            result.rdata = response[selected].rdata;
            result.rresp = response[selected].rresp;
            result.rvalid = response[selected].rvalid;
        end
        cpu_response = owner ? '0 : result;
        host_response = owner ? result : '0;
    end
    always @(posedge clk) begin : arbitrate
        bit grant;
        request_t next_source;
        if (rst) begin
            state <= IDLE;
            owner <= 0;
            last_owner <= 0;
            selected <= 0;
            aw_done <= 0;
            w_done <= 0;
        end else if (state == IDLE) begin
            // Round-robin prevents host polling from starving the processor.
            grant = (host.awvalid || host.arvalid) &&
                    (!(cpu.awvalid || cpu.arvalid) || !last_owner);
            next_source = grant ? host : cpu;
            if (next_source.awvalid || next_source.arvalid) begin
                owner <= grant;
                last_owner <= grant;
                selected <= decode(next_source.awvalid ? next_source.awaddr : next_source.araddr);
                state <= next_source.awvalid ? WRITE : READ;
                aw_done <= 0;
                w_done <= 0;
            end
        end else if (state == WRITE) begin
            if (source.awvalid && result.awready) aw_done <= 1;
            if (source.wvalid && result.wready) w_done <= 1;
            if (result.bvalid && source.bready) state <= IDLE;
        end else if (result.rvalid && source.rready) state <= IDLE;
    end
endmodule

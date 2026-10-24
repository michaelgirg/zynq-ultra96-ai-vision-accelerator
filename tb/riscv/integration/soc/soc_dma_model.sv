// Behavioral simple-mode DMA/DDR contract, NOT simulation of AMD encrypted IP.
// Control and stream clocks are independent. Command toggles cross into the
// stream domain; status is sampled behaviorally by AXI-Lite reads.
module soc_dma_model (
    input logic clk, axis_clk, rst,
    input wire soc_sim_bus_pkg::request_t request,
    output soc_sim_bus_pkg::response_t response,
    input int injection,
    output logic [31:0] tx_data,
    output logic [3:0] tx_keep,
    output logic tx_valid, tx_last,
    input logic tx_ready,
    input logic [31:0] rx_data,
    input logic [3:0] rx_keep,
    input logic rx_valid, rx_last,
    output logic rx_ready
);
    logic [31:0] ddr [0:4095];
    localparam logic [31:0] DDR_BASE = 32'h1000_0000;
    logic [31:0] tx_ctrl, rx_ctrl, tx_addr, rx_addr, tx_bytes, rx_bytes;
    logic aw_seen, w_seen;
    logic [31:0] awaddr, wdata;
    logic [3:0] wstrb;
    bit tx_toggle, rx_toggle, reset_toggle;
    logic [1:0] tx_sync, rx_sync, reset_sync;
    bit tx_seen, rx_seen, reset_seen;
    bit tx_active, rx_active;
    int tx_count, rx_count, axis_cycles;
    int starts = 0, resets = 0, input_stalls = 0, output_stalls = 0;
    int reset_countdown;
    wire tx_error = injection == 1 && tx_count >= 32 && tx_active;
    wire rx_error = injection == 2 && rx_count >= 32 && rx_active;
    assign response.awready = !aw_seen && !response.bvalid;
    assign response.wready = !w_seen && !response.bvalid;
    assign response.arready = !response.rvalid;
    function automatic int ddr_index(input logic [31:0] addr);
        if (addr < DDR_BASE || addr >= DDR_BASE + 16384 || addr[1:0] != 0)
            $fatal(1, "DMA outside modeled DDR: %h", addr);
        return int'((addr - DDR_BASE) >> 2);
    endfunction
    always @(posedge clk) begin
        if (rst) begin
            aw_seen <= 0; w_seen <= 0;
            response.bvalid <= 0; response.bresp <= 0;
            response.rvalid <= 0; response.rresp <= 0; response.rdata <= 0;
            tx_ctrl <= 0; rx_ctrl <= 0;
            tx_addr <= 0; rx_addr <= 0; tx_bytes <= 0; rx_bytes <= 0;
            tx_toggle <= 0; rx_toggle <= 0; reset_toggle <= 0;
            reset_countdown <= 0;
        end else begin
            if (reset_countdown > 0 && injection != 5) begin
                reset_countdown <= reset_countdown - 1;
                if (reset_countdown == 1) begin tx_ctrl <= 0; rx_ctrl <= 0; end
            end
            if (request.awvalid && response.awready) begin
                aw_seen <= 1; awaddr <= request.awaddr;
            end
            if (request.wvalid && response.wready) begin
                w_seen <= 1; wdata <= request.wdata; wstrb <= request.wstrb;
            end
            if (aw_seen && w_seen && !response.bvalid) begin
                aw_seen <= 0; w_seen <= 0;
                response.bvalid <= 1; response.bresp <= 0;
                if (wstrb != 15) $fatal(1, "DMA model requires full register writes");
                case (awaddr[7:0])
                    8'h00, 8'h30: begin
                        if (wdata[2]) begin
                            // PG021: resetting either channel resets the whole engine.
                            tx_ctrl <= 4; rx_ctrl <= 4;
                            reset_countdown <= 12; reset_toggle <= !reset_toggle;
                            resets <= resets + 1;
                        end else if (awaddr[7:0] == 0) tx_ctrl <= wdata;
                        else rx_ctrl <= wdata;
                    end
                    8'h18: tx_addr <= wdata;
                    8'h28: begin
                        if (!tx_ctrl[0] || !rx_ctrl[0] || rx_bytes != wdata)
                            $fatal(1, "MM2S launched before matching S2MM arm");
                        tx_bytes <= wdata; tx_toggle <= !tx_toggle;
                        starts <= starts + 1;
                    end
                    8'h48: rx_addr <= wdata;
                    8'h58: begin
                        if (!rx_ctrl[0]) $fatal(1, "S2MM not running");
                        rx_bytes <= wdata; rx_toggle <= !rx_toggle;
                    end
                    default: response.bresp <= 2;
                endcase
            end else if (response.bvalid && request.bready) response.bvalid <= 0;
            if (request.arvalid && response.arready) begin
                response.rvalid <= 1; response.rresp <= 0;
                case (request.araddr[7:0])
                    8'h00: response.rdata <= tx_ctrl;
                    8'h04: response.rdata <= tx_error ? 32'h10 : (tx_active ? 0 : 2);
                    8'h18: response.rdata <= tx_addr;
                    8'h28: response.rdata <= tx_bytes;
                    8'h30: response.rdata <= rx_ctrl;
                    8'h34: response.rdata <= rx_error ? 32'h10 : (rx_active ? 0 : 2);
                    8'h48: response.rdata <= rx_addr;
                    8'h58: response.rdata <= rx_bytes;
                    default: begin response.rdata <= 0; response.rresp <= 2; end
                endcase
            end else if (response.rvalid && request.rready) response.rvalid <= 0;
        end
    end
    // Registered source guarantees stable payload under backpressure. Injection
    // 3/5 hangs after a partial frame; 4 corrupts a real accepted TKEEP beat.
    always @(posedge axis_clk) begin
        if (rst) begin
            tx_sync <= 0; rx_sync <= 0; reset_sync <= 0;
            tx_seen <= 0; rx_seen <= 0; reset_seen <= 0;
            tx_active <= 0; rx_active <= 0;
            tx_count <= 0; rx_count <= 0; axis_cycles <= 0;
            tx_valid <= 0; tx_last <= 0; tx_data <= 0; tx_keep <= 15;
        end else begin
            axis_cycles <= axis_cycles + 1;
            tx_sync <= {tx_sync[0], tx_toggle};
            rx_sync <= {rx_sync[0], rx_toggle};
            reset_sync <= {reset_sync[0], reset_toggle};
            if (reset_sync[1] != reset_seen) begin
                reset_seen <= reset_sync[1];
                tx_active <= 0; rx_active <= 0; tx_valid <= 0; tx_last <= 0;
            end else begin
                if (rx_sync[1] != rx_seen) begin
                    rx_seen <= rx_sync[1]; rx_active <= 1; rx_count <= 0;
                end
                if (tx_sync[1] != tx_seen) begin
                    tx_seen <= tx_sync[1]; tx_active <= 1; tx_count <= 0;
                end
                if (tx_valid && tx_ready) begin
                    tx_count <= tx_count + 1;
                    tx_valid <= 0;
                    if (tx_last) tx_active <= 0;
                end
                if (tx_active && !tx_valid && axis_cycles % 7 != 0 &&
                    !tx_error && !((injection == 3 || injection == 5) && tx_count >= 32)) begin
                    tx_data <= ddr[ddr_index(tx_addr) + tx_count];
                    tx_keep <= (injection == 4 && tx_count == 20) ? 7 : 15;
                    tx_last <= (tx_count == int'(tx_bytes / 4) - 1);
                    tx_valid <= 1;
                end
                if (rx_valid && rx_ready) begin
                    if (rx_keep != 15 || rx_last != (rx_count == int'(rx_bytes / 4) - 1))
                        $fatal(1, "malformed accelerator output at beat %0d", rx_count);
                    ddr[ddr_index(rx_addr) + rx_count] <= rx_data;
                    rx_count <= rx_count + 1;
                    if (rx_last) rx_active <= 0;
                end
            end
            if (tx_valid && !tx_ready) input_stalls <= input_stalls + 1;
            if (rx_valid && !rx_ready) output_stalls <= output_stalls + 1;
        end
    end
    assign rx_ready = rx_active && !rx_error && axis_cycles % 11 >= 4;
endmodule

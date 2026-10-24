// Formal environment: arbitrary request traffic, slave delays/responses/reset.
// Safety only; no fairness or claim of progress against a nonresponding slave.
module rv32_axi_master_harness(input wire clk);
    (* anyseq *) reg rst;
    (* anyseq *) reg req_valid, req_write, resp_ready;
    (* anyseq *) reg [31:0] req_addr, req_wdata;
    (* anyseq *) reg [3:0] req_wstrb;
    (* anyseq *) reg M_AXI_AWREADY, M_AXI_WREADY, M_AXI_BVALID;
    (* anyseq *) reg M_AXI_ARREADY, M_AXI_RVALID;
    (* anyseq *) reg [1:0] M_AXI_BRESP, M_AXI_RRESP;
    (* anyseq *) reg [31:0] M_AXI_RDATA;
    wire req_ready, resp_valid, resp_fault;
    wire [31:0] resp_rdata, M_AXI_AWADDR, M_AXI_WDATA, M_AXI_ARADDR;
    wire [2:0] M_AXI_AWPROT, M_AXI_ARPROT;
    wire [3:0] M_AXI_WSTRB;
    wire M_AXI_AWVALID, M_AXI_WVALID, M_AXI_BREADY, M_AXI_ARVALID, M_AXI_RREADY;
    rv32_axi_lite_master dut (.*);

    reg past_valid = 0;
    reg pending = 0;
    reg [31:0] address, data, expected_rdata;
    reg [3:0] strobes;
    reg write_request, expected_fault;
    reg response_seen = 0;
    always @(posedge clk) begin
        past_valid <= 1;
        if (!past_valid) assume(rst);
        if (rst) begin pending <= 0; response_seen <= 0; end
        else begin
            if (req_valid && req_ready) begin
                assert(!pending);
                pending <= 1; response_seen <= 0;
                address <= req_addr; data <= req_wdata; strobes <= req_wstrb;
                write_request <= req_write;
            end
            if (M_AXI_AWVALID) begin
                assert(pending && write_request);
                assert(M_AXI_AWADDR == address && M_AXI_AWPROT == 0);
            end
            if (M_AXI_WVALID) begin
                assert(pending && write_request);
                assert(M_AXI_WDATA == data && M_AXI_WSTRB == strobes);
            end
            if (M_AXI_ARVALID) begin
                assert(pending && !write_request);
                assert(M_AXI_ARADDR == address && M_AXI_ARPROT == 0);
            end
            if (M_AXI_BVALID && M_AXI_BREADY) begin
                assert(pending && write_request && !response_seen);
                response_seen <= 1; expected_rdata <= 0;
                expected_fault <= M_AXI_BRESP != 0;
            end
            if (M_AXI_RVALID && M_AXI_RREADY) begin
                assert(pending && !write_request && !response_seen);
                response_seen <= 1; expected_rdata <= M_AXI_RDATA;
                expected_fault <= M_AXI_RRESP != 0;
            end
            if (resp_valid) begin
                assert(pending && response_seen);
                assert(resp_rdata == expected_rdata && resp_fault == expected_fault);
                if (resp_ready) pending <= 0;
            end
        end
        if (past_valid && !$past(rst) && !rst) begin
            if ($past(M_AXI_AWVALID && !M_AXI_AWREADY)) begin
                assert(M_AXI_AWVALID); assert($stable(M_AXI_AWADDR));
            end
            if ($past(M_AXI_WVALID && !M_AXI_WREADY)) begin
                assert(M_AXI_WVALID); assert($stable({M_AXI_WDATA, M_AXI_WSTRB}));
            end
            if ($past(M_AXI_ARVALID && !M_AXI_ARREADY)) begin
                assert(M_AXI_ARVALID); assert($stable(M_AXI_ARADDR));
            end
            if ($past(resp_valid && !resp_ready)) begin
                assert(resp_valid); assert($stable({resp_rdata, resp_fault}));
            end
        end
    end
endmodule

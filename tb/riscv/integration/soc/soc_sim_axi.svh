`define SOC_SIM_AXI(P, Q, R, W) \
    .P``_AWADDR(Q.awaddr[W-1:0]), .P``_AWPROT(Q.awprot), \
    .P``_AWVALID(Q.awvalid), .P``_AWREADY(R.awready), \
    .P``_WDATA(Q.wdata), .P``_WSTRB(Q.wstrb), \
    .P``_WVALID(Q.wvalid), .P``_WREADY(R.wready), \
    .P``_BRESP(R.bresp), .P``_BVALID(R.bvalid), .P``_BREADY(Q.bready), \
    .P``_ARADDR(Q.araddr[W-1:0]), .P``_ARPROT(Q.arprot), \
    .P``_ARVALID(Q.arvalid), .P``_ARREADY(R.arready), \
    .P``_RDATA(R.rdata), .P``_RRESP(R.rresp), \
    .P``_RVALID(R.rvalid), .P``_RREADY(Q.rready)

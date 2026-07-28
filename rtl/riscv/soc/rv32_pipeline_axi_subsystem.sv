module rv32_pipeline_axi_subsystem #(
    parameter int IMEM_WORDS = 16384,
    parameter int DMEM_WORDS = 16384,
    parameter string IMEM_HEX = "",
    parameter string DMEM_HEX = ""
) (
    input  logic        clk_i,
    input  logic        system_rst_i,
    input  logic        core_rst_i,
    output logic [31:0] current_pc_o,
    output logic [31:0] instruction_o,
    output logic        halted_o,
    output logic        illegal_instruction_o,
    output logic        instruction_fault_o,
    output logic        data_fault_o,

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
    output logic        M_AXI_RREADY,

    input  logic [15:0] S_AXI_IMEM_AWADDR,
    input  logic [2:0]  S_AXI_IMEM_AWPROT,
    input  logic        S_AXI_IMEM_AWVALID,
    output logic        S_AXI_IMEM_AWREADY,
    input  logic [31:0] S_AXI_IMEM_WDATA,
    input  logic [3:0]  S_AXI_IMEM_WSTRB,
    input  logic        S_AXI_IMEM_WVALID,
    output logic        S_AXI_IMEM_WREADY,
    output logic [1:0]  S_AXI_IMEM_BRESP,
    output logic        S_AXI_IMEM_BVALID,
    input  logic        S_AXI_IMEM_BREADY,
    input  logic [15:0] S_AXI_IMEM_ARADDR,
    input  logic [2:0]  S_AXI_IMEM_ARPROT,
    input  logic        S_AXI_IMEM_ARVALID,
    output logic        S_AXI_IMEM_ARREADY,
    output logic [31:0] S_AXI_IMEM_RDATA,
    output logic [1:0]  S_AXI_IMEM_RRESP,
    output logic        S_AXI_IMEM_RVALID,
    input  logic        S_AXI_IMEM_RREADY,

    input  logic [15:0] S_AXI_DMEM_AWADDR,
    input  logic [2:0]  S_AXI_DMEM_AWPROT,
    input  logic        S_AXI_DMEM_AWVALID,
    output logic        S_AXI_DMEM_AWREADY,
    input  logic [31:0] S_AXI_DMEM_WDATA,
    input  logic [3:0]  S_AXI_DMEM_WSTRB,
    input  logic        S_AXI_DMEM_WVALID,
    output logic        S_AXI_DMEM_WREADY,
    output logic [1:0]  S_AXI_DMEM_BRESP,
    output logic        S_AXI_DMEM_BVALID,
    input  logic        S_AXI_DMEM_BREADY,
    input  logic [15:0] S_AXI_DMEM_ARADDR,
    input  logic [2:0]  S_AXI_DMEM_ARPROT,
    input  logic        S_AXI_DMEM_ARVALID,
    output logic        S_AXI_DMEM_ARREADY,
    output logic [31:0] S_AXI_DMEM_RDATA,
    output logic [1:0]  S_AXI_DMEM_RRESP,
    output logic        S_AXI_DMEM_RVALID,
    input  logic        S_AXI_DMEM_RREADY
);
    logic core_reset;
    logic imem_req_valid, imem_req_ready, imem_req_write;
    logic [31:0] imem_req_addr, imem_req_wdata;
    logic [3:0] imem_req_wstrb;
    logic imem_resp_valid, imem_resp_ready, imem_resp_fault;
    logic [31:0] imem_resp_rdata;
    logic dmem_req_valid, dmem_req_ready, dmem_req_write;
    logic [31:0] dmem_req_addr, dmem_req_wdata;
    logic [3:0] dmem_req_wstrb;
    logic dmem_resp_valid, dmem_resp_ready, dmem_resp_fault;
    logic [31:0] dmem_resp_rdata;

    assign core_reset = system_rst_i || core_rst_i;

    rv32_pipeline_axi_top #(
        .IMEM_WORDS(IMEM_WORDS),
        .DMEM_WORDS(DMEM_WORDS),
        .IMEM_HEX  (IMEM_HEX),
        .DMEM_HEX  (DMEM_HEX)
    ) u_processor (
        .clk_i,
        .rst_i(core_reset),
        .memory_rst_i(system_rst_i),
        .current_pc_o,
        .instruction_o,
        .halted_o,
        .illegal_instruction_o,
        .instruction_fault_o,
        .data_fault_o,
        .M_AXI_AWADDR, .M_AXI_AWPROT, .M_AXI_AWVALID, .M_AXI_AWREADY,
        .M_AXI_WDATA, .M_AXI_WSTRB, .M_AXI_WVALID, .M_AXI_WREADY,
        .M_AXI_BRESP, .M_AXI_BVALID, .M_AXI_BREADY,
        .M_AXI_ARADDR, .M_AXI_ARPROT, .M_AXI_ARVALID, .M_AXI_ARREADY,
        .M_AXI_RDATA, .M_AXI_RRESP, .M_AXI_RVALID, .M_AXI_RREADY,
        .imem_host_req_valid(imem_req_valid),
        .imem_host_req_ready(imem_req_ready),
        .imem_host_req_write(imem_req_write),
        .imem_host_req_addr(imem_req_addr),
        .imem_host_req_wdata(imem_req_wdata),
        .imem_host_req_wstrb(imem_req_wstrb),
        .imem_host_resp_valid(imem_resp_valid),
        .imem_host_resp_ready(imem_resp_ready),
        .imem_host_resp_rdata(imem_resp_rdata),
        .imem_host_resp_fault(imem_resp_fault),
        .dmem_host_req_valid(dmem_req_valid),
        .dmem_host_req_ready(dmem_req_ready),
        .dmem_host_req_write(dmem_req_write),
        .dmem_host_req_addr(dmem_req_addr),
        .dmem_host_req_wdata(dmem_req_wdata),
        .dmem_host_req_wstrb(dmem_req_wstrb),
        .dmem_host_resp_valid(dmem_resp_valid),
        .dmem_host_resp_ready(dmem_resp_ready),
        .dmem_host_resp_rdata(dmem_resp_rdata),
        .dmem_host_resp_fault(dmem_resp_fault)
    );

    rv32_axi_memory_portal u_imem_portal (
        .S_AXI_ACLK(clk_i), .S_AXI_ARESETN(!system_rst_i),
        .S_AXI_AWADDR(S_AXI_IMEM_AWADDR), .S_AXI_AWPROT(S_AXI_IMEM_AWPROT),
        .S_AXI_AWVALID(S_AXI_IMEM_AWVALID), .S_AXI_AWREADY(S_AXI_IMEM_AWREADY),
        .S_AXI_WDATA(S_AXI_IMEM_WDATA), .S_AXI_WSTRB(S_AXI_IMEM_WSTRB),
        .S_AXI_WVALID(S_AXI_IMEM_WVALID), .S_AXI_WREADY(S_AXI_IMEM_WREADY),
        .S_AXI_BRESP(S_AXI_IMEM_BRESP), .S_AXI_BVALID(S_AXI_IMEM_BVALID),
        .S_AXI_BREADY(S_AXI_IMEM_BREADY),
        .S_AXI_ARADDR(S_AXI_IMEM_ARADDR), .S_AXI_ARPROT(S_AXI_IMEM_ARPROT),
        .S_AXI_ARVALID(S_AXI_IMEM_ARVALID), .S_AXI_ARREADY(S_AXI_IMEM_ARREADY),
        .S_AXI_RDATA(S_AXI_IMEM_RDATA), .S_AXI_RRESP(S_AXI_IMEM_RRESP),
        .S_AXI_RVALID(S_AXI_IMEM_RVALID), .S_AXI_RREADY(S_AXI_IMEM_RREADY),
        .mem_req_valid(imem_req_valid), .mem_req_ready(imem_req_ready),
        .mem_req_write(imem_req_write), .mem_req_addr(imem_req_addr),
        .mem_req_wdata(imem_req_wdata), .mem_req_wstrb(imem_req_wstrb),
        .mem_resp_valid(imem_resp_valid), .mem_resp_ready(imem_resp_ready),
        .mem_resp_rdata(imem_resp_rdata), .mem_resp_fault(imem_resp_fault)
    );

    rv32_axi_memory_portal u_dmem_portal (
        .S_AXI_ACLK(clk_i), .S_AXI_ARESETN(!system_rst_i),
        .S_AXI_AWADDR(S_AXI_DMEM_AWADDR), .S_AXI_AWPROT(S_AXI_DMEM_AWPROT),
        .S_AXI_AWVALID(S_AXI_DMEM_AWVALID), .S_AXI_AWREADY(S_AXI_DMEM_AWREADY),
        .S_AXI_WDATA(S_AXI_DMEM_WDATA), .S_AXI_WSTRB(S_AXI_DMEM_WSTRB),
        .S_AXI_WVALID(S_AXI_DMEM_WVALID), .S_AXI_WREADY(S_AXI_DMEM_WREADY),
        .S_AXI_BRESP(S_AXI_DMEM_BRESP), .S_AXI_BVALID(S_AXI_DMEM_BVALID),
        .S_AXI_BREADY(S_AXI_DMEM_BREADY),
        .S_AXI_ARADDR(S_AXI_DMEM_ARADDR), .S_AXI_ARPROT(S_AXI_DMEM_ARPROT),
        .S_AXI_ARVALID(S_AXI_DMEM_ARVALID), .S_AXI_ARREADY(S_AXI_DMEM_ARREADY),
        .S_AXI_RDATA(S_AXI_DMEM_RDATA), .S_AXI_RRESP(S_AXI_DMEM_RRESP),
        .S_AXI_RVALID(S_AXI_DMEM_RVALID), .S_AXI_RREADY(S_AXI_DMEM_RREADY),
        .mem_req_valid(dmem_req_valid), .mem_req_ready(dmem_req_ready),
        .mem_req_write(dmem_req_write), .mem_req_addr(dmem_req_addr),
        .mem_req_wdata(dmem_req_wdata), .mem_req_wstrb(dmem_req_wstrb),
        .mem_resp_valid(dmem_resp_valid), .mem_resp_ready(dmem_resp_ready),
        .mem_resp_rdata(dmem_resp_rdata), .mem_resp_fault(dmem_resp_fault)
    );
endmodule

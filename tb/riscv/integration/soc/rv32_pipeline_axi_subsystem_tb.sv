`timescale 1ns/1ps

module rv32_pipeline_axi_subsystem_tb;
    wire axi_timeout_o, axi_quarantined_o;
    wire [31:0] axi_fault_addr_o, axi_fault_info_o, axi_fault_wait_o;
    import rv32i_pkg::*;

    logic clk = 1'b0;
    logic system_rst = 1'b1;
    logic core_rst = 1'b1;
    logic halted;
    logic illegal_instruction;
    logic instruction_fault;
    logic data_fault;

    logic [31:0] M_AXI_AWADDR, M_AXI_WDATA, M_AXI_ARADDR;
    logic [2:0] M_AXI_AWPROT, M_AXI_ARPROT;
    logic M_AXI_AWVALID, M_AXI_WVALID, M_AXI_BREADY;
    logic M_AXI_ARVALID, M_AXI_RREADY;
    logic [3:0] M_AXI_WSTRB;

    logic [15:0] S_AXI_IMEM_AWADDR, S_AXI_IMEM_ARADDR;
    logic [2:0] S_AXI_IMEM_AWPROT, S_AXI_IMEM_ARPROT;
    logic S_AXI_IMEM_AWVALID, S_AXI_IMEM_AWREADY;
    logic [31:0] S_AXI_IMEM_WDATA;
    logic [3:0] S_AXI_IMEM_WSTRB;
    logic S_AXI_IMEM_WVALID, S_AXI_IMEM_WREADY;
    logic [1:0] S_AXI_IMEM_BRESP;
    logic S_AXI_IMEM_BVALID, S_AXI_IMEM_BREADY;
    logic S_AXI_IMEM_ARVALID, S_AXI_IMEM_ARREADY;
    logic [31:0] S_AXI_IMEM_RDATA;
    logic [1:0] S_AXI_IMEM_RRESP;
    logic S_AXI_IMEM_RVALID, S_AXI_IMEM_RREADY;

    logic [15:0] S_AXI_DMEM_AWADDR, S_AXI_DMEM_ARADDR;
    logic [2:0] S_AXI_DMEM_AWPROT, S_AXI_DMEM_ARPROT;
    logic S_AXI_DMEM_AWVALID, S_AXI_DMEM_AWREADY;
    logic [31:0] S_AXI_DMEM_WDATA;
    logic [3:0] S_AXI_DMEM_WSTRB;
    logic S_AXI_DMEM_WVALID, S_AXI_DMEM_WREADY;
    logic [1:0] S_AXI_DMEM_BRESP;
    logic S_AXI_DMEM_BVALID, S_AXI_DMEM_BREADY;
    logic S_AXI_DMEM_ARVALID, S_AXI_DMEM_ARREADY;
    logic [31:0] S_AXI_DMEM_RDATA;
    logic [1:0] S_AXI_DMEM_RRESP;
    logic S_AXI_DMEM_RVALID, S_AXI_DMEM_RREADY;

    integer checks = 0;

    always #5 clk = ~clk;

    rv32_pipeline_axi_subsystem #(
        .IMEM_WORDS(64),
        .DMEM_WORDS(64)
    ) dut (
        .S_AXI_ACLK(clk),
        .system_rst_i(system_rst),
        .core_rst_i(core_rst),
        .current_pc_o(),
        .instruction_o(),
        .halted_o(halted),
        .illegal_instruction_o(illegal_instruction),
        .instruction_fault_o(instruction_fault),
        .data_fault_o(data_fault),
        .M_AXI_AWADDR, .M_AXI_AWPROT, .M_AXI_AWVALID, .M_AXI_AWREADY(1'b0),
        .M_AXI_WDATA, .M_AXI_WSTRB, .M_AXI_WVALID, .M_AXI_WREADY(1'b0),
        .M_AXI_BRESP(2'b00), .M_AXI_BVALID(1'b0), .M_AXI_BREADY,
        .M_AXI_ARADDR, .M_AXI_ARPROT, .M_AXI_ARVALID, .M_AXI_ARREADY(1'b0),
        .M_AXI_RDATA(32'b0), .M_AXI_RRESP(2'b00),
        .M_AXI_RVALID(1'b0), .M_AXI_RREADY,
        .*
    );

    task automatic check(input logic condition, input string message);
        begin
            checks = checks + 1;
            if (!condition) begin
                $error("CHECK FAILED: %s", message);
                $fatal(1);
            end
        end
    endtask

    task automatic portal_write(
        input logic select_imem,
        input logic [15:0] address,
        input logic [31:0] data,
        input logic [3:0] strobes
    );
        begin
            @(negedge clk);
            if (select_imem) begin
                S_AXI_IMEM_AWADDR = address;
                S_AXI_IMEM_WDATA = data;
                S_AXI_IMEM_WSTRB = strobes;
                S_AXI_IMEM_AWVALID = 1'b1;
                S_AXI_IMEM_WVALID = 1'b1;
                do @(posedge clk); while (!(S_AXI_IMEM_AWREADY && S_AXI_IMEM_WREADY));
                @(negedge clk);
                S_AXI_IMEM_AWVALID = 1'b0;
                S_AXI_IMEM_WVALID = 1'b0;
                wait (S_AXI_IMEM_BVALID);
                check(S_AXI_IMEM_BRESP == 2'b00, "IMEM portal write response");
                S_AXI_IMEM_BREADY = 1'b1;
                @(posedge clk);
                @(negedge clk);
                S_AXI_IMEM_BREADY = 1'b0;
            end
            else begin
                S_AXI_DMEM_AWADDR = address;
                S_AXI_DMEM_WDATA = data;
                S_AXI_DMEM_WSTRB = strobes;
                S_AXI_DMEM_AWVALID = 1'b1;
                S_AXI_DMEM_WVALID = 1'b1;
                do @(posedge clk); while (!(S_AXI_DMEM_AWREADY && S_AXI_DMEM_WREADY));
                @(negedge clk);
                S_AXI_DMEM_AWVALID = 1'b0;
                S_AXI_DMEM_WVALID = 1'b0;
                wait (S_AXI_DMEM_BVALID);
                check(S_AXI_DMEM_BRESP == 2'b00, "DMEM portal write response");
                S_AXI_DMEM_BREADY = 1'b1;
                @(posedge clk);
                @(negedge clk);
                S_AXI_DMEM_BREADY = 1'b0;
            end
        end
    endtask

    task automatic portal_read(
        input logic select_imem,
        input logic [15:0] address,
        input logic [31:0] expected_data
    );
        begin
            @(negedge clk);
            if (select_imem) begin
                S_AXI_IMEM_ARADDR = address;
                S_AXI_IMEM_ARVALID = 1'b1;
                do @(posedge clk); while (!S_AXI_IMEM_ARREADY);
                @(negedge clk);
                S_AXI_IMEM_ARVALID = 1'b0;
                wait (S_AXI_IMEM_RVALID);
                check(S_AXI_IMEM_RRESP == 2'b00, "IMEM portal read response");
                check(S_AXI_IMEM_RDATA == expected_data, "IMEM portal readback");
                S_AXI_IMEM_RREADY = 1'b1;
                @(posedge clk);
                @(negedge clk);
                S_AXI_IMEM_RREADY = 1'b0;
            end
            else begin
                S_AXI_DMEM_ARADDR = address;
                S_AXI_DMEM_ARVALID = 1'b1;
                do @(posedge clk); while (!S_AXI_DMEM_ARREADY);
                @(negedge clk);
                S_AXI_DMEM_ARVALID = 1'b0;
                wait (S_AXI_DMEM_RVALID);
                check(S_AXI_DMEM_RRESP == 2'b00, "DMEM portal read response");
                check(S_AXI_DMEM_RDATA == expected_data, "DMEM portal readback");
                S_AXI_DMEM_RREADY = 1'b1;
                @(posedge clk);
                @(negedge clk);
                S_AXI_DMEM_RREADY = 1'b0;
            end
        end
    endtask

    initial begin
        S_AXI_IMEM_AWADDR = '0; S_AXI_IMEM_AWPROT = '0;
        S_AXI_IMEM_AWVALID = 1'b0; S_AXI_IMEM_WDATA = '0;
        S_AXI_IMEM_WSTRB = '0; S_AXI_IMEM_WVALID = 1'b0;
        S_AXI_IMEM_BREADY = 1'b0; S_AXI_IMEM_ARADDR = '0;
        S_AXI_IMEM_ARPROT = '0; S_AXI_IMEM_ARVALID = 1'b0;
        S_AXI_IMEM_RREADY = 1'b0;
        S_AXI_DMEM_AWADDR = '0; S_AXI_DMEM_AWPROT = '0;
        S_AXI_DMEM_AWVALID = 1'b0; S_AXI_DMEM_WDATA = '0;
        S_AXI_DMEM_WSTRB = '0; S_AXI_DMEM_WVALID = 1'b0;
        S_AXI_DMEM_BREADY = 1'b0; S_AXI_DMEM_ARADDR = '0;
        S_AXI_DMEM_ARPROT = '0; S_AXI_DMEM_ARVALID = 1'b0;
        S_AXI_DMEM_RREADY = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk);
        system_rst = 1'b0;

        // ARM loads and verifies local memories while RV32 remains in reset.
        portal_write(1'b1, 16'h0000, INSTRUCTION_EBREAK, 4'b1111);
        portal_write(1'b1, 16'h0004, INSTRUCTION_NOP, 4'b1111);
        portal_read(1'b1, 16'h0000, INSTRUCTION_EBREAK);
        portal_write(1'b0, 16'h0000, 32'hDEAD_BEEF, 4'b1111);
        portal_read(1'b0, 16'h0000, 32'hDEAD_BEEF);
        check(!halted, "core remains reset during host loading");

        @(negedge clk);
        core_rst = 1'b0;
        repeat (100) begin
            @(posedge clk);
            if (halted) break;
        end
        check(halted, "core boots the host-loaded EBREAK image");
        check(!illegal_instruction && !instruction_fault && !data_fault,
              "host-loaded boot image halts without faults");

        $display("PASS: RV32 host boot portals (%0d checks)", checks);
        $finish;
    end
endmodule

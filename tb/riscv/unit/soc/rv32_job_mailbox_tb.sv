`timescale 1ns/1ps

module rv32_job_mailbox_tb;
    logic clk = 1'b0;
    logic resetn = 1'b0;
    logic [11:0] awaddr;
    logic [2:0] awprot = '0;
    logic awvalid;
    logic awready;
    logic [31:0] wdata;
    logic [3:0] wstrb;
    logic wvalid;
    logic wready;
    logic [1:0] bresp;
    logic bvalid;
    logic bready;
    logic [11:0] araddr;
    logic [2:0] arprot = '0;
    logic arvalid;
    logic arready;
    logic [31:0] rdata;
    logic [1:0] rresp;
    logic rvalid;
    logic rready;
    logic rv32_resetn;
    integer checks = 0;

    always #5 clk = ~clk;

    rv32_job_mailbox dut (
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(resetn),
        .S_AXI_AWADDR(awaddr), .S_AXI_AWPROT(awprot),
        .S_AXI_AWVALID(awvalid), .S_AXI_AWREADY(awready),
        .S_AXI_WDATA(wdata), .S_AXI_WSTRB(wstrb),
        .S_AXI_WVALID(wvalid), .S_AXI_WREADY(wready),
        .S_AXI_BRESP(bresp), .S_AXI_BVALID(bvalid), .S_AXI_BREADY(bready),
        .S_AXI_ARADDR(araddr), .S_AXI_ARPROT(arprot),
        .S_AXI_ARVALID(arvalid), .S_AXI_ARREADY(arready),
        .S_AXI_RDATA(rdata), .S_AXI_RRESP(rresp),
        .S_AXI_RVALID(rvalid), .S_AXI_RREADY(rready),
        .rv32_resetn(rv32_resetn)
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

    task automatic axi_write(
        input logic [11:0] address,
        input logic [31:0] data,
        input logic [1:0] expected_response,
        input logic address_first
    );
        begin
            awaddr = address;
            wdata = data;
            wstrb = 4'b1111;
            if (address_first) begin
                awvalid = 1'b1;
                do @(posedge clk); while (!awready);
                @(negedge clk); awvalid = 1'b0;
                repeat (2) @(posedge clk);
                @(negedge clk); wvalid = 1'b1;
                do @(posedge clk); while (!wready);
                @(negedge clk); wvalid = 1'b0;
            end
            else begin
                wvalid = 1'b1;
                do @(posedge clk); while (!wready);
                @(negedge clk); wvalid = 1'b0;
                repeat (2) @(posedge clk);
                @(negedge clk); awvalid = 1'b1;
                do @(posedge clk); while (!awready);
                @(negedge clk); awvalid = 1'b0;
            end
            wait (bvalid);
            check(bresp == expected_response, "write response");
            repeat (2) @(posedge clk);
            check(bvalid && bresp == expected_response, "write response backpressure");
            @(negedge clk); bready = 1'b1;
            @(posedge clk);
            @(negedge clk); bready = 1'b0;
        end
    endtask

    task automatic axi_read(
        input logic [11:0] address,
        input logic [31:0] expected_data,
        input logic [1:0] expected_response
    );
        begin
            @(negedge clk);
            araddr = address;
            arvalid = 1'b1;
            do @(posedge clk); while (!arready);
            @(negedge clk); arvalid = 1'b0;
            wait (rvalid);
            check(rdata == expected_data, "read data");
            check(rresp == expected_response, "read response");
            repeat (2) @(posedge clk);
            check(rvalid && rdata == expected_data, "read response backpressure");
            @(negedge clk); rready = 1'b1;
            @(posedge clk);
            @(negedge clk); rready = 1'b0;
        end
    endtask

    initial begin
        awaddr = '0;
        awvalid = 1'b0;
        wdata = '0;
        wstrb = 4'b1111;
        wvalid = 1'b0;
        bready = 1'b0;
        araddr = '0;
        arvalid = 1'b0;
        rready = 1'b0;

        repeat (3) @(posedge clk);
        @(negedge clk); resetn = 1'b1;

        axi_read(12'h028, 32'h5A42_4D42, 2'b00);
        axi_read(12'h004, 32'h0, 2'b00);
        axi_read(12'h02C, 32'h0, 2'b00);
        axi_write(12'h02C, 32'h1, 2'b00, 1'b0);
        axi_read(12'h02C, 32'h1, 2'b00);
        axi_write(12'h008, 32'h1000_0000, 2'b00, 1'b1);
        axi_write(12'h00C, 32'h1000_1000, 2'b00, 1'b0);
        axi_write(12'h010, 32'd784, 2'b00, 1'b1);
        axi_write(12'h014, 32'd3, 2'b00, 1'b0);
        axi_write(12'h018, 32'd128, 2'b00, 1'b1);
        axi_write(12'h01C, 32'h42, 2'b00, 1'b0);
        axi_write(12'h000, 32'h1, 2'b00, 1'b1);
        axi_read(12'h004, 32'h1, 2'b00);

        // Descriptor mutation and duplicate submit are rejected while pending.
        axi_write(12'h008, 32'hDEAD_BEEF, 2'b10, 1'b0);
        axi_write(12'h000, 32'h1, 2'b10, 1'b1);
        axi_write(12'h000, 32'h2, 2'b00, 1'b0);
        axi_read(12'h004, 32'h2, 2'b00);

        axi_write(12'h020, 32'h600D, 2'b00, 1'b1);
        axi_write(12'h000, 32'h4, 2'b00, 1'b0);
        axi_read(12'h004, 32'h4, 2'b00);
        axi_read(12'h020, 32'h600D, 2'b00);
        axi_write(12'h000, 32'h10, 2'b00, 1'b1);
        axi_read(12'h004, 32'h0, 2'b00);

        // A zero-length descriptor may not be submitted.
        axi_write(12'h010, 32'd0, 2'b00, 1'b0);
        axi_write(12'h000, 32'h1, 2'b10, 1'b1);
        axi_read(12'h002, 32'h0, 2'b10);

        $display("PASS: rv32_job_mailbox_tb (%0d checks)", checks);
        $finish;
    end
endmodule

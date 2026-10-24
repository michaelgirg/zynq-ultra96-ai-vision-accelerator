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
    logic irq, axi_timeout = 0, axi_quarantined = 0;
    logic [31:0] axi_fault_addr = 0, axi_fault_info = 0, axi_fault_wait = 0;
    logic [63:0] cycle_count = 0, expected_submit = 0, expected_claim = 0, expected_end = 0;
    logic was_bvalid = 0;
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
        .rv32_resetn(rv32_resetn), .irq, .axi_timeout, .axi_quarantined,
        .axi_fault_addr, .axi_fault_info, .axi_fault_wait
    );

    // Independent bus-observed timestamp scoreboard (no DUT state peeks).
    always @(posedge clk) begin
        if (!resetn) begin cycle_count = 0; was_bvalid = 0; end
        else begin
            cycle_count = cycle_count + 1;
            #1;
            if (bvalid && !was_bvalid && bresp == 0 && awaddr == 0 && wstrb == 15) begin
                case (wdata)
                    1: expected_submit = cycle_count - 1;
                    2: expected_claim = cycle_count - 1;
                    4, 8: expected_end = cycle_count - 1;
                    default: begin end
                endcase
            end
            was_bvalid = bvalid;
        end
    end

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
        input logic address_first,
        input logic [3:0] strobes = 4'b1111
    );
        begin
            awaddr = address;
            wdata = data;
            wstrb = strobes;
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
        axi_read(12'h030, 32'h0001_0000, 2'b00);
        check(!irq, "interrupt masked after reset");
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
        axi_write(12'h03C, 1, 2'b10, 1'b0);

        // Descriptor mutation and duplicate submit are rejected while pending.
        axi_write(12'h008, 32'hDEAD_BEEF, 2'b10, 1'b0);
        axi_write(12'h000, 32'h1, 2'b10, 1'b1);
        axi_write(12'h000, 32'h2, 2'b00, 1'b0);
        axi_read(12'h004, 32'h2, 2'b00);

        axi_write(12'h020, 32'h600D, 2'b00, 1'b1);
        axi_write(12'h000, 32'h4, 2'b00, 1'b0);
        axi_read(12'h004, 32'h4, 2'b00);
        axi_read(12'h020, 32'h600D, 2'b00);
        axi_read(12'h040, expected_submit[31:0], 0);
        axi_read(12'h044, expected_submit[63:32], 0);
        axi_read(12'h048, expected_claim[31:0], 0);
        axi_read(12'h04C, expected_claim[63:32], 0);
        axi_read(12'h050, expected_end[31:0], 0);
        axi_read(12'h054, expected_end[63:32], 0);
        axi_read(12'h058, 32'(expected_end - expected_submit), 0);
        axi_read(12'h05C, 0, 0);
        axi_read(12'h060, 1, 0);
        axi_read(12'h034, 1, 0);
        check(!irq, "masked completion still latches cause");
        axi_write(12'h038, 1, 0, 0);
        check(irq, "unmasking a pending completion asserts level IRQ");
        axi_write(12'h034, 1, 0, 1, 0);
        check(irq, "zero-strobe W1C is a no-op");
        axi_write(12'h034, 1, 2, 0, 1);
        check(irq, "partial W1C rejected");
        axi_write(12'h034, 1, 0, 1);
        check(!irq, "W1C deasserts IRQ without acknowledging job");
        axi_read(12'h004, 4, 0);
        axi_write(12'h000, 32'h10, 2'b00, 1'b1);
        axi_read(12'h004, 32'h0, 2'b00);
        axi_read(12'h050, expected_end[31:0], 0);

        axi_write(12'h038, 2, 0, 0);
        axi_write(12'h01C, 43, 0, 1);
        axi_write(12'h000, 1, 0, 0);
        axi_read(12'h048, 0, 0);
        axi_read(12'h058, 0, 0);
        axi_write(12'h000, 2, 0, 1);
        axi_write(12'h024, 6, 0, 0);
        axi_write(12'h000, 8, 0, 1);
        check(irq, "firmware failure interrupt");
        axi_read(12'h034, 2, 0);
        axi_read(12'h064, 1, 0);
        axi_read(12'h068, 1, 0);
        axi_read(12'h070, 1, 0);
        axi_read(12'h074, 43, 0);
        axi_read(12'h078, 6, 0);
        axi_read(12'h088, expected_end[31:0], 0);
        axi_write(12'h000, 16, 0, 0);
        check(!irq, "ACK clears completion/failure IRQ causes");
        axi_write(12'h01C, 44, 0, 1);
        axi_write(12'h000, 1, 0, 0);
        axi_write(12'h000, 2, 0, 1);
        axi_write(12'h024, 3, 0, 0);
        axi_write(12'h000, 8, 0, 1);
        axi_read(12'h070, 1, 0);
        axi_read(12'h074, 43, 0);
        axi_read(12'h078, 6, 0);
        axi_read(12'h064, 2, 0);
        axi_read(12'h068, 1, 0);
        axi_write(12'h000, 16, 0, 0);
        axi_write(12'h03C, 1, 0, 1);
        axi_read(12'h060, 0, 0);
        axi_read(12'h064, 0, 0);
        axi_read(12'h068, 0, 0);
        axi_read(12'h070, 0, 0);
        axi_write(12'h030, 0, 2, 0);
        axi_write(12'h038, 8, 2, 1);

        // A zero-length descriptor may not be submitted.
        axi_write(12'h010, 32'd0, 2'b00, 1'b0);
        axi_write(12'h000, 32'h1, 2'b10, 1'b1);
        axi_read(12'h002, 32'h0, 2'b10);

        // An independent bridge fault remains observable even with no CPU response.
        axi_write(12'h038, 4, 0, 0);
        @(negedge clk);
        axi_timeout = 1; axi_quarantined = 1;
        axi_fault_addr = 32'hA001_0004;
        axi_fault_info = 32'h10; axi_fault_wait = 8;
        repeat (4) @(negedge clk);
        check(irq, "bridge watchdog interrupts host independently of firmware");
        axi_read(12'h034, 4, 0);
        axi_read(12'h06C, 1, 0);
        axi_read(12'h070, 2, 0);
        axi_read(12'h074, 0, 0);
        axi_read(12'h07C, 32'hA001_0004, 0);
        axi_read(12'h080, 32'h10, 0);
        axi_read(12'h084, 8, 0);
        axi_read(12'h094, 32'hA001_0004, 0);
        axi_read(12'h098, 32'h10, 0);
        axi_read(12'h09C, 8, 0);
        axi_write(12'h034, 4, 0, 1);
        check(!irq, "watchdog interrupt acknowledgement does not clear quarantine");
        axi_read(12'h090, 3, 0);
        axi_write(12'h03C, 1, 2, 0);
        axi_write(12'h02C, 1, 2, 1);
        axi_write(12'h010, 784, 0, 0);
        axi_write(12'h000, 1, 2, 1);
        axi_read(12'h06C, 1, 0);
        @(negedge clk); resetn = 0; axi_timeout = 0; axi_quarantined = 0;
        repeat (3) @(negedge clk); resetn = 1;
        axi_read(12'h090, 0, 0);
        axi_read(12'h070, 0, 0);
        axi_read(12'h034, 0, 0);
        check(!irq, "system reset clears diagnostic/IRQ state");

        $display("PASS: rv32_job_mailbox_tb (%0d checks)", checks);
        $finish;
    end
endmodule

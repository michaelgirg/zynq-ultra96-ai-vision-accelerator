`timescale 1ns/1ps
module rv32_axi_watchdog_tb;
    logic clk = 0, rst = 1, processor_reset = 0;
    always #5 clk = !clk;
    logic req_valid = 0, req_ready, req_write = 0, resp_valid, resp_ready = 0, resp_fault;
    logic [31:0] req_addr = 0, req_wdata = 0, resp_rdata;
    logic [3:0] req_wstrb = 0;
    logic [31:0] M_AXI_AWADDR, M_AXI_WDATA, M_AXI_ARADDR, M_AXI_RDATA = 0;
    logic [2:0] M_AXI_AWPROT, M_AXI_ARPROT;
    logic [3:0] M_AXI_WSTRB;
    logic M_AXI_AWVALID, M_AXI_AWREADY = 0, M_AXI_WVALID, M_AXI_WREADY = 0;
    logic M_AXI_BVALID = 0, M_AXI_BREADY, M_AXI_ARVALID, M_AXI_ARREADY = 0;
    logic M_AXI_RVALID = 0, M_AXI_RREADY;
    logic [1:0] M_AXI_BRESP = 0, M_AXI_RRESP = 0;
    logic watchdog_timeout, quarantined;
    logic [31:0] watchdog_addr, watchdog_info, watchdog_wait;
    logic [11:0] mb_awaddr = 0, mb_araddr = 0;
    logic [31:0] mb_wdata = 0, mb_rdata;
    logic mb_awvalid = 0, mb_awready, mb_wvalid = 0, mb_wready;
    logic mb_bvalid, mb_bready = 0, mb_arvalid = 0, mb_arready;
    logic mb_rvalid, mb_rready = 0, mailbox_irq;
    logic [1:0] mb_bresp, mb_rresp;
    int checks = 0;
    bit [5:0] channels_hit = 0;
    rv32_axi_lite_master #(.WATCHDOG_CYCLES(8)) dut (.*);
    // Independent host slave port remains available while the RV32 master is
    // stalled. This is not a model of SmartConnect's internal arbitration.
    rv32_job_mailbox mailbox (
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(!rst),
        .S_AXI_AWADDR(mb_awaddr), .S_AXI_AWPROT(3'b0),
        .S_AXI_AWVALID(mb_awvalid), .S_AXI_AWREADY(mb_awready),
        .S_AXI_WDATA(mb_wdata), .S_AXI_WSTRB(4'hF),
        .S_AXI_WVALID(mb_wvalid), .S_AXI_WREADY(mb_wready),
        .S_AXI_BRESP(mb_bresp), .S_AXI_BVALID(mb_bvalid), .S_AXI_BREADY(mb_bready),
        .S_AXI_ARADDR(mb_araddr), .S_AXI_ARPROT(3'b0),
        .S_AXI_ARVALID(mb_arvalid), .S_AXI_ARREADY(mb_arready),
        .S_AXI_RDATA(mb_rdata), .S_AXI_RRESP(mb_rresp),
        .S_AXI_RVALID(mb_rvalid), .S_AXI_RREADY(mb_rready), .rv32_resetn(),
        .irq(mailbox_irq), .axi_timeout(watchdog_timeout), .axi_quarantined(quarantined),
        .axi_fault_addr(watchdog_addr), .axi_fault_info(watchdog_info), .axi_fault_wait(watchdog_wait)
    );

    task automatic check(input bit condition, input string message);
        checks++;
        if (!condition) $fatal(1, "%s", message);
    endtask
    task automatic mb_write(input logic [11:0] address, input logic [31:0] data);
        @(negedge clk); mb_awaddr = address; mb_wdata = data;
        mb_awvalid = 1; mb_wvalid = 1;
        @(negedge clk); mb_awvalid = 0; mb_wvalid = 0;
        wait (mb_bvalid);
        check(mb_bresp == 0, "host mailbox write while RV32 target stalled");
        @(negedge clk); mb_bready = 1;
        @(negedge clk); mb_bready = 0;
    endtask
    task automatic mb_read(input logic [11:0] address, input logic [31:0] expected);
        @(negedge clk); mb_araddr = address; mb_arvalid = 1;
        @(negedge clk); mb_arvalid = 0;
        wait (mb_rvalid);
        check(mb_rresp == 0 && mb_rdata === expected, "host reads real watchdog mailbox diagnostics");
        @(negedge clk); mb_rready = 1;
        @(negedge clk); mb_rready = 0;
    endtask
    task automatic reset_system;
        @(negedge clk); rst = 1; processor_reset = 0;
        req_valid = 0; resp_ready = 0;
        M_AXI_AWREADY = 0; M_AXI_WREADY = 0; M_AXI_BVALID = 0;
        M_AXI_ARREADY = 0; M_AXI_RVALID = 0;
        repeat (3) @(negedge clk);
        rst = 0;
        check(req_ready && !quarantined && !watchdog_timeout, "coordinated reset restores service");
    endtask
    task automatic start(input bit writing);
        @(negedge clk);
        check(req_ready, "bridge idle before request");
        req_valid = 1; req_write = writing; req_addr = 32'hA001_0004;
        req_wdata = 32'h1234_5678; req_wstrb = 5;
        @(negedge clk); req_valid = 0;
    endtask
    task automatic accept_write(input bit address_channel, data_channel);
        M_AXI_AWREADY = address_channel; M_AXI_WREADY = data_channel;
        @(negedge clk); M_AXI_AWREADY = 0; M_AXI_WREADY = 0;
    endtask
    task automatic accept_read;
        M_AXI_ARREADY = 1;
        @(negedge clk); M_AXI_ARREADY = 0;
    endtask
    task automatic wait_timeout(input logic [4:0] mask, input bit writing);
        // No progress for exactly eight rising edges; firing early is a defect.
        for (int i = 0; i < 7; i++) begin
            @(negedge clk);
            check(!watchdog_timeout && !resp_valid, "no premature timeout/processor completion");
        end
        @(negedge clk);
        check(watchdog_timeout && quarantined, "timeout fires on eighth stalled cycle");
        check(watchdog_addr == req_addr && watchdog_info == ((writing ? 256 : 0) | mask) &&
            watchdog_wait == 8, "first timeout address/direction/channel/wait capture");
        check(!req_ready && !resp_valid, "timeout never fabricates a completion");
        repeat (12) @(negedge clk);
        check(watchdog_info == ((writing ? 256 : 0) | mask), "first timeout stays immutable");
        check(!mailbox_irq, "masked timeout still recorded");
        mb_read('h34, 4); mb_read('h6C, 1); mb_read('h90, 3);
        mb_read('h94, req_addr); mb_read('h98, (writing ? 256 : 0) | mask); mb_read('h9C, 8);
        mb_write('h38, 4);
        check(mailbox_irq, "real master timeout drives mailbox level IRQ");
        mb_write('h34, 4);
        check(!mailbox_irq && quarantined, "IRQ W1C never releases real bridge quarantine");
    endtask
    task automatic drain(input bit writing, input bit abandoned = 0);
        if (writing) begin
            // Finish whichever independent AW/W handshakes remain pending.
            accept_write(1, 1);
            M_AXI_BVALID = 1;
            @(negedge clk); M_AXI_BVALID = 0;
        end else begin
            if (M_AXI_ARVALID) accept_read();
            M_AXI_RVALID = 1; M_AXI_RDATA = 32'hCAFE_BABE;
            @(negedge clk); M_AXI_RVALID = 0;
        end
        if (!abandoned) begin
            check(resp_valid && resp_fault, "late OKAY becomes a processor fault after draining");
            repeat (10) @(negedge clk);
            check(resp_valid && resp_fault, "late processor fault survives backpressure");
            resp_ready = 1;
            @(negedge clk); resp_ready = 0;
        end else begin
            repeat (3) @(negedge clk);
            check(!resp_valid, "no stale response delivered to rebooted processor");
        end
        check(!req_ready && quarantined, "drain does not unlock quarantine");
        req_valid = 1;
        repeat (12) @(negedge clk);
        check(!M_AXI_AWVALID && !M_AXI_WVALID && !M_AXI_ARVALID && !req_ready,
            "quarantine rejects all later requests");
        req_valid = 0;
    endtask
    initial begin
        // AW-only, W-only, B, AR, R, and simultaneous AW/W stalls.
        for (int channel = 0; channel < 6; channel++) begin
            reset_system();
            start(channel < 3 || channel == 5);
            case (channel)
                0: begin accept_write(0, 1); wait_timeout(1, 1); end
                1: begin accept_write(1, 0); wait_timeout(2, 1); end
                2: begin accept_write(1, 1); wait_timeout(4, 1); end
                3: wait_timeout(8, 0);
                4: begin accept_read(); wait_timeout(16, 0); end
                5: wait_timeout(3, 1);
            endcase
            drain(channel < 3 || channel == 5);
            channels_hit[channel] = 1;
        end
        reset_system();
        start(1);
        repeat (7) @(negedge clk);
        accept_write(1, 0); // Progress on the deadline wins over timeout.
        check(!watchdog_timeout, "boundary AW handshake prevents timeout");
        repeat (7) @(negedge clk);
        accept_write(0, 1);
        check(!watchdog_timeout, "independent W progress restarts interval");
        repeat (7) @(negedge clk);
        M_AXI_BVALID = 1;
        @(negedge clk); M_AXI_BVALID = 0;
        repeat (20) @(negedge clk);
        check(resp_valid && !resp_fault && !watchdog_timeout,
            "processor backpressure is not an AXI timeout");
        resp_ready = 1;
        @(negedge clk); resp_ready = 0;
        check(req_ready, "non-timeout completion permits next request");

        reset_system();
        start(1); accept_write(1, 0);
        processor_reset = 1;
        @(negedge clk); processor_reset = 0;
        check(quarantined && M_AXI_WVALID && !M_AXI_AWVALID,
            "CPU reset preserves the unaccepted half of an AXI write");
        drain(1, 1);
        check(!watchdog_timeout, "CPU abandonment is distinct from slave timeout");
        reset_system();
        processor_reset = 1;
        repeat (20) @(negedge clk);
        check(!quarantined, "CPU held reset at boot is safe while bridge idle");
        processor_reset = 0;
        @(negedge clk);
        check(req_ready && channels_hit == 63, "all six stalled-channel scenarios exercised");
        $display("PASS: rv32_axi_watchdog_tb (%0d checks; 6/6 channel scenarios)", checks);
        $finish;
    end
    initial begin #100000; $fatal(1, "watchdog testbench deadline"); end
endmodule

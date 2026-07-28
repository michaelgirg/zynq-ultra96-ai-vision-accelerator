`timescale 1ns/1ps

module rv32_axi_lite_master_tb;
    logic clk = 1'b0;
    logic rst = 1'b1;

    logic        req_valid;
    logic        req_ready;
    logic        req_write;
    logic [31:0] req_addr;
    logic [31:0] req_wdata;
    logic [3:0]  req_wstrb;
    logic        resp_valid;
    logic        resp_ready;
    logic [31:0] resp_rdata;
    logic        resp_fault;

    logic [31:0] M_AXI_AWADDR;
    logic [2:0]  M_AXI_AWPROT;
    logic        M_AXI_AWVALID;
    logic        M_AXI_AWREADY;
    logic [31:0] M_AXI_WDATA;
    logic [3:0]  M_AXI_WSTRB;
    logic        M_AXI_WVALID;
    logic        M_AXI_WREADY;
    logic [1:0]  M_AXI_BRESP;
    logic        M_AXI_BVALID;
    logic        M_AXI_BREADY;
    logic [31:0] M_AXI_ARADDR;
    logic [2:0]  M_AXI_ARPROT;
    logic        M_AXI_ARVALID;
    logic        M_AXI_ARREADY;
    logic [31:0] M_AXI_RDATA;
    logic [1:0]  M_AXI_RRESP;
    logic        M_AXI_RVALID;
    logic        M_AXI_RREADY;

    integer checks;
    integer write_tests;
    integer read_tests;
    integer aw_first_tests;
    integer w_first_tests;
    integer simultaneous_tests;
    integer fault_tests;

    always #5 clk = ~clk;

    rv32_axi_lite_master dut (.*);

    task automatic check(input logic condition, input string message);
        begin
            checks = checks + 1;
            if (!condition) begin
                $error("CHECK FAILED: %s", message);
                $fatal(1);
            end
        end
    endtask

    task automatic clear_slave;
        begin
            M_AXI_AWREADY = 1'b0;
            M_AXI_WREADY  = 1'b0;
            M_AXI_BRESP   = 2'b00;
            M_AXI_BVALID  = 1'b0;
            M_AXI_ARREADY = 1'b0;
            M_AXI_RDATA   = '0;
            M_AXI_RRESP   = 2'b00;
            M_AXI_RVALID  = 1'b0;
        end
    endtask

    task automatic submit_request(
        input logic        write_request,
        input logic [31:0] address,
        input logic [31:0] write_data,
        input logic [3:0]  write_strobes
    );
        begin
            @(negedge clk);
            check(req_ready, "request interface ready before submission");
            req_valid = 1'b1;
            req_write = write_request;
            req_addr  = address;
            req_wdata = write_data;
            req_wstrb = write_strobes;
            @(posedge clk);
            #1;
            check(!req_ready, "only one request may be outstanding");
            @(negedge clk);
            req_valid = 1'b0;
        end
    endtask

    task automatic complete_processor_response(
        input integer response_delay,
        input logic [31:0] expected_data,
        input logic        expected_fault
    );
        integer delay_index;
        begin
            for (delay_index = 0; delay_index < response_delay; delay_index = delay_index + 1) begin
                @(negedge clk);
                resp_ready = 1'b0;
                check(resp_valid, "processor response remains valid under backpressure");
                check(resp_rdata == expected_data, "processor response data remains stable");
                check(resp_fault == expected_fault, "processor response fault remains stable");
            end

            @(negedge clk);
            check(resp_valid, "processor response becomes valid");
            check(resp_rdata == expected_data, "processor receives expected data");
            check(resp_fault == expected_fault, "processor receives expected fault status");
            resp_ready = 1'b1;
            @(posedge clk);
            #1;
            check(req_ready, "bridge accepts a new request after response handshake");
            @(negedge clk);
            resp_ready = 1'b0;
        end
    endtask

    task automatic run_write(
        input logic [31:0] address,
        input logic [31:0] data,
        input logic [3:0]  strobes,
        input integer      aw_delay,
        input integer      w_delay,
        input integer      b_delay,
        input logic [1:0]  bresp,
        input integer      processor_delay
    );
        integer cycle_index;
        integer aw_cycle;
        integer w_cycle;
        integer response_index;
        logic aw_done;
        logic w_done;
        begin
            write_tests = write_tests + 1;
            submit_request(1'b1, address, data, strobes);

            aw_done = 1'b0;
            w_done = 1'b0;
            aw_cycle = -1;
            w_cycle = -1;
            cycle_index = 0;
            while (!(aw_done && w_done)) begin
                M_AXI_AWREADY = !aw_done && (cycle_index >= aw_delay);
                M_AXI_WREADY  = !w_done && (cycle_index >= w_delay);
                #1;
                if (!aw_done && M_AXI_AWREADY) begin
                    check(M_AXI_AWVALID, "AWVALID asserted until address handshake");
                    check(M_AXI_AWADDR == address, "write address is preserved");
                    check(M_AXI_AWPROT == 3'b000, "write uses unprivileged data protection attributes");
                end
                if (!w_done && M_AXI_WREADY) begin
                    check(M_AXI_WVALID, "WVALID asserted until data handshake");
                    check(M_AXI_WDATA == data, "write data is preserved");
                    check(M_AXI_WSTRB == strobes, "write strobes are preserved");
                end
                @(posedge clk);
                #1;
                if (!aw_done && M_AXI_AWREADY) begin
                    aw_done = 1'b1;
                    aw_cycle = cycle_index;
                end
                if (!w_done && M_AXI_WREADY) begin
                    w_done = 1'b1;
                    w_cycle = cycle_index;
                end
                cycle_index = cycle_index + 1;
            end
            @(negedge clk);
            M_AXI_AWREADY = 1'b0;
            M_AXI_WREADY = 1'b0;

            if (aw_cycle < w_cycle)
                aw_first_tests = aw_first_tests + 1;
            else if (w_cycle < aw_cycle)
                w_first_tests = w_first_tests + 1;
            else
                simultaneous_tests = simultaneous_tests + 1;

            for (response_index = 0; response_index < b_delay; response_index = response_index + 1)
                @(posedge clk);
            @(negedge clk);
            M_AXI_BRESP = bresp;
            M_AXI_BVALID = 1'b1;
            #1;
            check(M_AXI_BREADY, "bridge accepts the write response");
            @(posedge clk);
            @(negedge clk);
            M_AXI_BVALID = 1'b0;
            M_AXI_BRESP = 2'b00;

            if (bresp != 2'b00)
                fault_tests = fault_tests + 1;
            complete_processor_response(processor_delay, 32'b0, bresp != 2'b00);
        end
    endtask

    task automatic run_read(
        input logic [31:0] address,
        input logic [31:0] data,
        input integer      ar_delay,
        input integer      r_delay,
        input logic [1:0]  rresp,
        input integer      processor_delay
    );
        integer delay_index;
        begin
            read_tests = read_tests + 1;
            submit_request(1'b0, address, 32'b0, 4'b0000);

            for (delay_index = 0; delay_index < ar_delay; delay_index = delay_index + 1) begin
                @(posedge clk);
                #1;
                check(M_AXI_ARVALID, "ARVALID remains asserted under backpressure");
                check(M_AXI_ARADDR == address, "read address remains stable");
            end
            @(negedge clk);
            M_AXI_ARREADY = 1'b1;
            #1;
            check(M_AXI_ARVALID, "bridge handshakes the read address");
            check(M_AXI_ARADDR == address, "bridge presents expected read address");
            check(M_AXI_ARPROT == 3'b000, "read uses unprivileged data protection attributes");
            @(posedge clk);
            @(negedge clk);
            M_AXI_ARREADY = 1'b0;

            for (delay_index = 0; delay_index < r_delay; delay_index = delay_index + 1)
                @(posedge clk);
            @(negedge clk);
            M_AXI_RDATA = data;
            M_AXI_RRESP = rresp;
            M_AXI_RVALID = 1'b1;
            #1;
            check(M_AXI_RREADY, "bridge accepts the read response");
            @(posedge clk);
            @(negedge clk);
            M_AXI_RVALID = 1'b0;
            M_AXI_RRESP = 2'b00;
            M_AXI_RDATA = '0;

            if (rresp != 2'b00)
                fault_tests = fault_tests + 1;
            complete_processor_response(processor_delay, data, rresp != 2'b00);
        end
    endtask

    task automatic reset_during_partial_write;
        begin
            submit_request(1'b1, 32'hA000_0040, 32'hCAFE_BABE, 4'b1111);
            M_AXI_AWREADY = 1'b1;
            M_AXI_WREADY = 1'b0;
            @(posedge clk);
            #1;
            check(!M_AXI_AWVALID, "write address can complete independently");
            check(M_AXI_WVALID, "write data remains pending after address handshake");
            @(negedge clk);
            M_AXI_AWREADY = 1'b0;
            rst = 1'b1;
            @(posedge clk);
            #1;
            check(req_ready, "reset returns bridge to idle");
            check(!M_AXI_AWVALID && !M_AXI_WVALID && !M_AXI_ARVALID,
                  "reset cancels outstanding AXI channel activity");
            @(negedge clk);
            rst = 1'b0;
        end
    endtask

    initial begin
        integer test_index;
        integer selector;
        logic [1:0] response_code;
        logic [31:0] random_address;
        logic [31:0] random_data;

        checks = 0;
        write_tests = 0;
        read_tests = 0;
        aw_first_tests = 0;
        w_first_tests = 0;
        simultaneous_tests = 0;
        fault_tests = 0;
        req_valid = 1'b0;
        req_write = 1'b0;
        req_addr = '0;
        req_wdata = '0;
        req_wstrb = '0;
        resp_ready = 1'b0;
        clear_slave();

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        run_write(32'hA000_0000, 32'h0123_4567, 4'b1111, 0, 3, 2, 2'b00, 2);
        run_write(32'hA001_0010, 32'h89AB_CDEF, 4'b0011, 4, 0, 0, 2'b10, 0);
        run_write(32'hA002_0000, 32'h55AA_00FF, 4'b1100, 2, 2, 3, 2'b00, 3);
        run_read(32'hA000_0004, 32'h1357_9BDF, 4, 3, 2'b00, 2);
        run_read(32'hA001_0004, 32'h2468_ACE0, 0, 0, 2'b11, 0);

        for (test_index = 0; test_index < 100; test_index = test_index + 1) begin
            random_address = 32'hA000_0000 | (($urandom & 32'h0003_FFFF) & 32'hFFFF_FFFC);
            random_data = $urandom;
            selector = $urandom_range(0, 15);
            response_code = (selector == 0) ? 2'b10 :
                            (selector == 1) ? 2'b11 : 2'b00;
            if ($urandom_range(0, 1) == 0)
                run_write(random_address, random_data,
                          $urandom_range(1, 15),
                          $urandom_range(0, 5),
                          $urandom_range(0, 5),
                          $urandom_range(0, 4),
                          response_code,
                          $urandom_range(0, 4));
            else
                run_read(random_address, random_data,
                         $urandom_range(0, 5),
                         $urandom_range(0, 4),
                         response_code,
                         $urandom_range(0, 4));
        end

        reset_during_partial_write();
        run_read(32'hA000_0008, 32'hFEED_FACE, 1, 1, 2'b00, 1);

        check(write_tests >= 40, "random regression exercises writes");
        check(read_tests >= 40, "random regression exercises reads");
        check(aw_first_tests > 0, "regression covers AW-before-W ordering");
        check(w_first_tests > 0, "regression covers W-before-AW ordering");
        check(simultaneous_tests > 0, "regression covers simultaneous AW/W ordering");
        check(fault_tests > 0, "regression covers AXI error responses");

        $display("PASS: RV32 AXI4-Lite master (%0d checks, %0d writes, %0d reads, %0d faults)",
                 checks, write_tests, read_tests, fault_tests);
        $finish;
    end

    initial begin
        #200000;
        $fatal(1, "TIMEOUT");
    end
endmodule

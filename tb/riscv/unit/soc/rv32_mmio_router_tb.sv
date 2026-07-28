module rv32_mmio_router_tb;

    localparam int TARGET_LOCAL = 0;
    localparam int TARGET_MMIO = 1;

    logic clk;
    logic rst;

    logic        cpu_req_valid;
    logic        cpu_req_ready;
    logic        cpu_req_write;
    logic [31:0] cpu_req_addr;
    logic [31:0] cpu_req_wdata;
    logic [2:0]  cpu_req_funct3;
    logic        cpu_resp_valid;
    logic        cpu_resp_ready;
    logic [31:0] cpu_resp_rdata;
    logic        cpu_resp_fault;

    logic        local_req_valid;
    logic        local_req_ready;
    logic        local_req_write;
    logic [31:0] local_req_addr;
    logic [31:0] local_req_wdata;
    logic [2:0]  local_req_funct3;
    logic        local_resp_valid;
    logic        local_resp_ready;
    logic [31:0] local_resp_rdata;
    logic        local_resp_fault;

    logic        mmio_req_valid;
    logic        mmio_req_ready;
    logic        mmio_req_write;
    logic [31:0] mmio_req_addr;
    logic [31:0] mmio_req_wdata;
    logic [3:0]  mmio_req_wstrb;
    logic        mmio_resp_valid;
    logic        mmio_resp_ready;
    logic [31:0] mmio_resp_rdata;
    logic        mmio_resp_fault;

    int checks;
    int errors;

    rv32_mmio_router dut (.*);

    always #5 clk = ~clk;

    task automatic check(input logic condition, input string message);
        checks++;
        if (!condition) begin
            errors++;
            $error("CHECK FAILED: %s", message);
        end
    endtask

    task automatic drive_idle;
        cpu_req_valid = 1'b0;
        cpu_req_write = 1'b0;
        cpu_req_addr = '0;
        cpu_req_wdata = '0;
        cpu_req_funct3 = 3'b010;
        cpu_resp_ready = 1'b0;
        local_req_ready = 1'b0;
        local_resp_valid = 1'b0;
        local_resp_rdata = '0;
        local_resp_fault = 1'b0;
        mmio_req_ready = 1'b0;
        mmio_resp_valid = 1'b0;
        mmio_resp_rdata = '0;
        mmio_resp_fault = 1'b0;
    endtask

    task automatic run_target_transaction(
        input int target,
        input logic write,
        input logic [31:0] address,
        input logic [31:0] write_data,
        input logic [2:0] funct3,
        input logic [31:0] response_data,
        input logic response_fault,
        input int request_delay,
        input int response_delay,
        input int cpu_delay
    );
        @(negedge clk);
        cpu_req_valid = 1'b1;
        cpu_req_write = write;
        cpu_req_addr = address;
        cpu_req_wdata = write_data;
        cpu_req_funct3 = funct3;

        repeat (request_delay) begin
            @(posedge clk);
            if (target == TARGET_LOCAL) begin
                check(local_req_valid, "local request must remain valid");
                check(!mmio_req_valid, "local request must bypass MMIO");
            end
            else begin
                check(mmio_req_valid, "MMIO request must remain valid");
                check(!local_req_valid, "MMIO request must bypass cache");
            end
            check(!cpu_req_ready, "CPU request must observe target backpressure");
        end

        @(negedge clk);
        if (target == TARGET_LOCAL)
            local_req_ready = 1'b1;
        else
            mmio_req_ready = 1'b1;

        @(posedge clk);
        check(cpu_req_ready, "request must be accepted with target ready");
        if (target == TARGET_LOCAL) begin
            check(local_req_valid && !mmio_req_valid,
                  "accepted local request must be one-hot");
            check(local_req_write == write, "local write flag mismatch");
            check(local_req_addr == address, "local address mismatch");
            check(local_req_wdata == write_data, "local write data mismatch");
            check(local_req_funct3 == funct3, "local funct3 mismatch");
        end
        else begin
            check(mmio_req_valid && !local_req_valid,
                  "accepted MMIO request must be one-hot");
            check(mmio_req_write == write, "MMIO write flag mismatch");
            check(mmio_req_addr == address, "MMIO address mismatch");
            check(mmio_req_wdata == write_data, "MMIO write data mismatch");
            check(mmio_req_wstrb == 4'b1111, "MMIO word strobe mismatch");
        end

        @(negedge clk);
        cpu_req_valid = 1'b0;
        local_req_ready = 1'b0;
        mmio_req_ready = 1'b0;

        repeat (response_delay) begin
            @(posedge clk);
            check(!cpu_resp_valid, "response must not appear before target valid");
        end

        @(negedge clk);
        if (target == TARGET_LOCAL) begin
            local_resp_valid = 1'b1;
            local_resp_rdata = response_data;
            local_resp_fault = response_fault;
        end
        else begin
            mmio_resp_valid = 1'b1;
            mmio_resp_rdata = response_data;
            mmio_resp_fault = response_fault;
        end

        repeat (cpu_delay + 1) begin
            @(posedge clk);
            check(cpu_resp_valid, "selected response must reach CPU");
            check(cpu_resp_rdata == response_data, "response data mismatch");
            check(cpu_resp_fault == response_fault, "response fault mismatch");
            if (target == TARGET_LOCAL)
                check(!local_resp_ready, "local response must see CPU backpressure");
            else
                check(!mmio_resp_ready, "MMIO response must see CPU backpressure");
        end

        @(negedge clk);
        cpu_resp_ready = 1'b1;
        @(posedge clk);
        check(cpu_resp_valid, "response must remain valid through handshake");
        if (target == TARGET_LOCAL)
            check(local_resp_ready, "local response ready must follow CPU");
        else
            check(mmio_resp_ready, "MMIO response ready must follow CPU");

        @(negedge clk);
        cpu_resp_ready = 1'b0;
        local_resp_valid = 1'b0;
        mmio_resp_valid = 1'b0;
        @(posedge clk);
        check(!cpu_resp_valid, "router must return idle after response");
    endtask

    task automatic run_fault_transaction(
        input logic write,
        input logic [31:0] address,
        input logic [2:0] funct3
    );
        @(negedge clk);
        cpu_req_valid = 1'b1;
        cpu_req_write = write;
        cpu_req_addr = address;
        cpu_req_wdata = 32'hbad0_f00d;
        cpu_req_funct3 = funct3;
        local_req_ready = 1'b1;
        mmio_req_ready = 1'b1;

        @(posedge clk);
        check(cpu_req_ready, "faulting request must be accepted");
        check(!local_req_valid && !mmio_req_valid,
              "faulting request must not reach a target");

        @(negedge clk);
        cpu_req_valid = 1'b0;
        local_req_ready = 1'b0;
        mmio_req_ready = 1'b0;

        repeat (2) begin
            @(posedge clk);
            check(cpu_resp_valid, "fault response must remain valid");
            check(cpu_resp_fault, "fault response must assert fault");
            check(cpu_resp_rdata == 32'b0, "fault read data must be zero");
            check(!local_req_valid && !mmio_req_valid,
                  "fault response must not issue a request");
        end

        @(negedge clk);
        cpu_resp_ready = 1'b1;
        @(posedge clk);
        check(cpu_resp_valid && cpu_resp_fault,
              "fault response must handshake cleanly");

        @(negedge clk);
        cpu_resp_ready = 1'b0;
        @(posedge clk);
        check(!cpu_resp_valid, "fault handshake must return router idle");
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        checks = 0;
        errors = 0;
        drive_idle();

        repeat (3) @(posedge clk);
        @(negedge clk);
        rst = 1'b0;

        // Local space retains byte/halfword/word semantics and cache faults.
        run_target_transaction(TARGET_LOCAL, 1'b0, 32'h0000_0000,
                               '0, 3'b010, 32'h1122_3344, 1'b0, 2, 1, 2);
        run_target_transaction(TARGET_LOCAL, 1'b1, 32'h0000_ffff,
                               32'ha5a5_5a5a, 3'b000, '0, 1'b1, 1, 2, 0);

        // Every software-visible MMIO window and both operation directions.
        run_target_transaction(TARGET_MMIO, 1'b1, 32'ha000_0000,
                               32'h0000_0001, 3'b010, '0, 1'b0, 3, 2, 2);
        run_target_transaction(TARGET_MMIO, 1'b0, 32'ha000_0ffc,
                               '0, 3'b010, 32'hfeed_cafe, 1'b0, 0, 3, 1);
        run_target_transaction(TARGET_MMIO, 1'b1, 32'ha001_fffc,
                               32'h1234_5678, 3'b010, '0, 1'b1, 1, 1, 0);
        run_target_transaction(TARGET_MMIO, 1'b0, 32'ha002_0000,
                               '0, 3'b010, 32'hc001_c0de, 1'b0, 2, 0, 3);

        // Gaps, ARM-only windows, subword MMIO, and misalignment all fault.
        run_fault_transaction(1'b0, 32'h0001_0000, 3'b010);
        run_fault_transaction(1'b1, 32'ha000_1000, 3'b010);
        run_fault_transaction(1'b0, 32'ha003_0000, 3'b010);
        run_fault_transaction(1'b1, 32'ha000_0000, 3'b000);
        run_fault_transaction(1'b0, 32'ha001_0002, 3'b010);

        if (errors == 0)
            $display("PASS: rv32_mmio_router_tb (%0d checks)", checks);
        else
            $fatal(1, "FAIL: rv32_mmio_router_tb (%0d errors, %0d checks)",
                   errors, checks);

        $finish;
    end

endmodule

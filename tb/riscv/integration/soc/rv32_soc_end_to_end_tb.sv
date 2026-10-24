`timescale 1ns/1ps
`include "soc_sim_axi.svh"
// Real CPU/cache/RAM portals + mailbox + dual-clock accelerator. Only host,
// interconnect arbitration and simple-mode DMA/DDR are behavioral models.
module rv32_soc_end_to_end_tb #(
    parameter int AXIS_HALF_PERIOD_PS = 3333
);
    import soc_sim_bus_pkg::*;
    localparam logic [31:0] ACC = 32'hA000_0000, MB = 32'hA002_0000;
    localparam logic [31:0] INPUT_ADDR = 32'h1000_0000, OUTPUT_ADDR = 32'h1000_1000;
    logic clk = 0, axis_clk = 0, rst = 1;
    always #5 clk = !clk;
    always #(AXIS_HALF_PERIOD_PS * 1ps) axis_clk = !axis_clk;
    request_t cpu, host = '0, target [5];
    response_t cpu_response, host_response, accelerator_response, response [5];
    logic resetn, halted, illegal_instruction, instruction_fault, data_fault;
    logic [31:0] pc;
    logic [31:0] tx_data, rx_data;
    logic [3:0] tx_keep, rx_keep;
    logic tx_valid, tx_ready, tx_last, rx_valid, rx_ready, rx_last, irq;
    int injection = 0, jobs = 0, frames = 0, compared = 0;
    logic [7:0] input_pixels [784];
    logic [31:0] expected [784], config_words [44], image [16384];
    string firmware_dir = "software/riscv/build/e2e";
    string output_dir = "generated/experiments/soc-e2e";

    soc_sim_fabric fabric (.clk, .rst, .cpu, .host, .cpu_response,
        .host_response, .target, .response);
    rv32_pipeline_axi_subsystem processor (
        .S_AXI_ACLK(clk), .system_rst_i(rst), .core_rst_i(!resetn),
        .current_pc_o(pc), .instruction_o(), .halted_o(halted),
        .illegal_instruction_o(illegal_instruction),
        .instruction_fault_o(instruction_fault), .data_fault_o(data_fault),
        `SOC_SIM_AXI(M_AXI, cpu, cpu_response, 32),
        `SOC_SIM_AXI(S_AXI_IMEM, target[3], response[3], 16),
        `SOC_SIM_AXI(S_AXI_DMEM, target[4], response[4], 16)
    );
    rv32_job_mailbox mailbox (
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(!rst), .rv32_resetn(resetn),
        `SOC_SIM_AXI(S_AXI, target[2], response[2], 12)
    );
    axis_preprocess_vector_cdc accelerator (
        .S_AXI_ACLK(clk), .S_AXI_ARESETN(!rst),
        .AXIS_ACLK(axis_clk), .AXIS_ARESETN(!rst),
        `SOC_SIM_AXI(S_AXI, target[0], accelerator_response, 8),
        .S_AXIS_TDATA(tx_data), .S_AXIS_TKEEP(tx_keep), .S_AXIS_TVALID(tx_valid),
        .S_AXIS_TREADY(tx_ready), .S_AXIS_TLAST(tx_last),
        .M_AXIS_TDATA(rx_data), .M_AXIS_TKEEP(rx_keep), .M_AXIS_TVALID(rx_valid),
        .M_AXIS_TREADY(rx_ready), .M_AXIS_TLAST(rx_last), .irq
    );
    soc_dma_model dma (.clk, .axis_clk, .rst,
        .request(target[1]), .response(response[1]), .injection,
        .tx_data, .tx_keep, .tx_valid, .tx_last, .tx_ready,
        .rx_data, .rx_keep, .rx_valid, .rx_last, .rx_ready);
    always_comb begin
        response[0] = accelerator_response;
        if (injection == 6 && target[0].araddr[7:0] == 'h70)
            response[0].rdata = accelerator_response.rdata ^ 1;
        if (injection == 7 && target[0].araddr[7:0] == 'h74)
            response[0].rdata = 32'h0002_0000; // old, non-recoverable checkpoint
    end

    // Any processor fault is fatal, including faults while the host is loading
    // or acknowledging jobs. Read-only observation, never hierarchical preload.
    always @(posedge clk) if (!rst && resetn &&
        (halted || illegal_instruction || instruction_fault || data_fault))
        $fatal(1, "processor fault pc=%h halt=%b illegal=%b ifault=%b dfault=%b",
            pc, halted, illegal_instruction, instruction_fault, data_fault);

    task automatic host_write(input logic [31:0] address, value,
                              input logic [1:0] expected_response = 0);
        @(negedge clk);
        host.awaddr = address; host.awvalid = 1;
        host.wdata = value; host.wstrb = 15; host.wvalid = 0;
        // Deliberately separate address and data and delay BREADY.
        fork
            begin
                do @(posedge clk); while (!host_response.awready);
                @(negedge clk); host.awvalid = 0;
            end
            begin
                repeat (2) @(negedge clk);
                host.wvalid = 1;
                do @(posedge clk); while (!host_response.wready);
                @(negedge clk); host.wvalid = 0;
            end
        join
        repeat (2) @(negedge clk);
        host.bready = 1;
        do @(posedge clk); while (!host_response.bvalid);
        if (host_response.bresp !== expected_response)
            $fatal(1, "host write %h response %b expected %b", address,
                host_response.bresp, expected_response);
        @(negedge clk); host.bready = 0;
    endtask
    task automatic host_read(input logic [31:0] address, output logic [31:0] value);
        @(negedge clk); host.araddr = address; host.arvalid = 1;
        do @(posedge clk); while (!host_response.arready);
        @(negedge clk); host.arvalid = 0;
        repeat (2) @(negedge clk);
        host.rready = 1;
        do @(posedge clk); while (!host_response.rvalid);
        value = host_response.rdata;
        if (host_response.rresp !== 0) $fatal(1, "host read %h failed", address);
        @(negedge clk); host.rready = 0;
    endtask
    task automatic load_portal(input string path, input logic [31:0] base);
        int fd, count, scanned;
        logic [31:0] value;
        count = 0;
        fd = $fopen(path, "r");
        if (!fd) $fatal(1, "missing compiled image %s", path);
        while (!$feof(fd)) begin
            scanned = $fscanf(fd, "%h", value);
            if (scanned == 1) begin
                if (count >= 16384) $fatal(1, "firmware image exceeds memory");
                image[count] = value;
                host_write(base + 4 * count, value);
                count++;
            end else if (!$feof(fd)) $fatal(1, "malformed firmware image");
        end
        $fclose(fd);
        for (int i = 0; i < count; i++) begin
            host_read(base + 4 * i, value);
            if (value !== image[i]) $fatal(1, "portal readback mismatch %h", base + 4*i);
        end
        $display("PASS: host portal loaded/read back %0d words at %h", count, base);
    endtask
    task automatic program_vector(input bit candidate);
        string path;
        path = candidate ? "generated/candidates/vector_conv4/classifier/vector_front_config.mem" :
                           "generated/classifier/vector_front_config.mem";
        $readmemh(path, config_words);
        for (int f = 0; f < 4; f++) for (int t = 0; t < 11; t++) begin
            if ($isunknown(config_words[f*11+t])) $fatal(1, "missing coefficient");
            host_write(ACC + 'h60, (f << 4) | t);
            host_write(ACC + 'h64, config_words[f*11+t]);
        end
        host_write(ACC + 'h68, 1);
    endtask
    task automatic prepare_frame(input int sample, mode, input bit candidate = 0);
        string name, golden;
        name = $sformatf("sample_00%0d", sample);
        $readmemh({"generated/test_vectors/", name, "_input.mem"}, input_pixels);
        case (mode)
            0: golden = {"generated/test_vectors/", name, "_threshold.mem"};
            1: golden = {"generated/test_vectors/", name, "_sobel.mem"};
            2: golden = {"generated/test_vectors/", name, "_conv.mem"};
            3: golden = candidate ? {"generated/candidates/vector_conv4/classifier/", name, ".mem"} :
                                   {"generated/classifier/", name, ".mem"};
        endcase
        $readmemh(golden, expected);
        for (int i = 0; i < 784; i++) begin
            dma.ddr[i] = {24'b0, input_pixels[i]};
            dma.ddr[1024 + i] = 32'hDEAD_BEEF;
            if ($isunknown(expected[i])) $fatal(1, "incomplete golden %s", golden);
        end
        dma.ddr[1023] = 32'hC0FF_EE01;
        dma.ddr[1808] = 32'hC0FF_EE02;
    endtask
    task automatic job(input int mode, error = 0, fault = 0,
        input logic [31:0] bytes = 3136, input logic [31:0] src = INPUT_ADDR,
        input logic [31:0] dst = OUTPUT_ADDR, input logic [31:0] threshold = 128);
        logic [31:0] status, value;
        int before_starts, polls;
        before_starts = dma.starts;
        injection = fault;
        jobs++;
        host_write(MB + 'h08, src); host_write(MB + 'h0C, dst);
        host_write(MB + 'h10, bytes); host_write(MB + 'h14, mode);
        host_write(MB + 'h18, threshold); host_write(MB + 'h1C, jobs);
        host_write(MB, 1);
        polls = 0;
        do begin
            host_read(MB + 4, status);
            if (++polls > 60000) $fatal(1, "job %0d timed out pc=%h status=%h", jobs, pc, status);
        end while (!(status & 12));
        if (status !== (error == 0 ? 4 : 8))
            $fatal(1, "job %0d terminal status %h expected error %0d", jobs, status, error);
        host_read(MB + 'h24, value);
        if (value !== error) $fatal(1, "job %0d error=%0d expected %0d", jobs, value, error);
        host_read(MB + 'h20, value);
        if (value !== (error == 0 ? 'h600D : 0)) $fatal(1, "wrong mailbox result");
        host_read(MB + 'h1C, value);
        if (value !== jobs) $fatal(1, "lost job identity");
        if ((error == 1 || error == 2 || (error == 7 && fault == 0)) && dma.starts != before_starts)
            $fatal(1, "invalid descriptor launched DMA");
        if (error == 0) begin
            if (dma.tx_active || dma.rx_active || dma.tx_count != 784 || dma.rx_count != 784)
                $fatal(1, "job completed without exact DMA frame");
            for (int i = 0; i < 784; i++) begin
                if (dma.ddr[1024+i] !== expected[i])
                    $fatal(1, "job %0d mode %0d beat %0d actual=%h golden=%h", jobs, mode,
                        i, dma.ddr[1024+i], expected[i]);
                compared++;
            end
            frames++;
        end
        if (dma.ddr[1023] !== 32'hC0FF_EE01 || dma.ddr[1808] !== 32'hC0FF_EE02)
            $fatal(1, "DMA wrote outside output frame");
        host_write(MB, 16);
        host_read(MB + 4, status);
        if (status !== 0) $fatal(1, "ACK failed to release mailbox");
        $display("PASS: SoC job=%0d mode=%0d expected_error=%0d fault=%0d polls=%0d",
            jobs, mode, error, fault, polls);
        injection = 0;
    endtask
    task automatic save_vector(input int sample, input bit candidate);
        int fd;
        string path, model_name;
        // Assign to a string before formatting: packed-string ternaries pad
        // the shorter literal with a leading space in older Questa versions.
        if (candidate) model_name = "candidate";
        else model_name = "baseline";
        path = $sformatf("%s/%s_sample_00%0d.mem", output_dir, model_name, sample);
        fd = $fopen(path, "w");
        if (!fd) $fatal(1, "cannot write captured features %s", path);
        for (int i = 0; i < 784; i++) $fdisplay(fd, "%08h", dma.ddr[1024+i]);
        $fclose(fd);
    endtask
    initial begin : scenario
        logic [31:0] value;
        int ignored;
        ignored = $value$plusargs("FIRMWARE_DIR=%s", firmware_dir);
        ignored = $value$plusargs("OUTPUT_DIR=%s", output_dir);
        repeat (8) @(negedge clk); rst = 0;
        host_read(MB + 'h2C, value);
        if (value !== 0) $fatal(1, "core not held reset at boot");
        load_portal({firmware_dir, "/controller_imem.mem"}, 32'hA003_0000);
        load_portal({firmware_dir, "/controller_dmem.mem"}, 32'hA004_0000);
        // Exercise a genuine DMEM word through both AXI write/read paths.
        host_write(32'hA004_7000, 32'h51A7_C0DE);
        host_read(32'hA004_7000, value);
        if (value !== 32'h51A7_C0DE) $fatal(1, "DMEM portal mismatch");
        host_write(MB + 'h2C, 1);
        program_vector(0);
        for (int mode = 0; mode < 4; mode++) for (int sample = 0; sample < 8; sample++) begin
            prepare_frame(sample, mode); job(mode);
            if (mode == 3) save_vector(sample, 0);
        end
        program_vector(1);
        for (int sample = 0; sample < 8; sample++) begin
            prepare_frame(sample, 3, 1); job(3); save_vector(sample, 1);
        end
        // Invalid descriptors must have no DMA side effects; every rejection
        // is followed by a successful full frame without resetting the core.
        for (int invalid = 0; invalid < 12; invalid++) begin
            prepare_frame(0, 0);
            case (invalid)
                0: job(0, 2, 0, 3132);
                1: job(0, 2, 0, 3140);
                2: job(0, 2, 0, 3136, INPUT_ADDR + 1);
                3: job(0, 2, 0, 3136, INPUT_ADDR, OUTPUT_ADDR + 2);
                4: job(0, 2, 0, 3136, 32'hA000_0000);
                5: job(0, 2, 0, 3136, INPUT_ADDR, 32'hFFFF_FC00);
                6: job(4, 2);
                7: job(0, 2, 0, 3136, INPUT_ADDR, OUTPUT_ADDR, 256);
                8: job(0, 2, 0, 3136, 0);
                9: job(0, 2, 0, 3136, INPUT_ADDR, INPUT_ADDR + 4);
                10: job(0, 2, 0, 3136, INPUT_ADDR, 32'h7FFF_FC00);
                11: job(0, 2, 0, 2);
            endcase
            job(0);
        end
        // Halted MM2S, halted S2MM, partial-frame timeout, and bad TKEEP.
        // Interrupt each mode, then run the next mode without resetting the CPU.
        for (int fault = 1; fault <= 4; fault++) begin
            for (int mode = 0; mode < 4; mode++) begin
                prepare_frame(0, mode, 1);
                job(mode, fault == 1 ? 3 : fault == 2 ? 4 : fault == 3 ? 6 : 5, fault);
                prepare_frame(1, (mode+1)%4, 1); job((mode+1)%4);
            end
        end
        for (int fault = 6; fault <= 7; fault++) begin
            prepare_frame(0, 0); job(0, 1, fault); job(0);
        end
        // Stuck reset must fail closed. ACK is not permission to reuse DMA.
        prepare_frame(0, 0); job(0, 7, 5); job(0, 7);
        if (dma.input_stalls == 0 || dma.output_stalls == 0)
            $fatal(1, "stream backpressure was not exercised");
        $display("PASS: end-to-end SoC jobs=%0d frames=%0d compared=%0d axis_half_ps=%0d resets=%0d",
            jobs, frames, compared, AXIS_HALF_PERIOD_PS, dma.resets);
        $finish;
    end
    initial begin
        #200ms;
        $fatal(1, "end-to-end simulation watchdog pc=%h", pc);
    end
endmodule

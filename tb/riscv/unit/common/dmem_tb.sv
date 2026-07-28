`timescale 1 ns / 100 ps

module dmem_tb #(
    parameter int NUM_RANDOM_TESTS = 3000,
    parameter int DEPTH = 64
);
    import rv32i_pkg::*;

    logic        clk = 1'b0;
    logic [31:0] addr;
    logic [31:0] wr_data;
    logic [2:0]  funct3;
    logic        mem_read;
    logic        mem_write;
    logic [31:0] rd_data;
    logic        access_fault;

    logic [31:0] model [0:DEPTH-1];
    int errors = 0;
    int operation_hits [0:7];
    int byte_lane_hits [0:3];
    int fault_hits = 0;

    dmem #(
        .DEPTH(DEPTH)
    ) DUT (.*);

    initial begin : generate_clock
        forever #5 clk <= ~clk;
    end

    function automatic logic [31:0] model_read(
        input logic [31:0] test_addr,
        input logic [2:0] test_funct3
    );
        logic [31:0] word;
        logic [7:0] selected_byte;
        logic [15:0] selected_half;

        word = model[test_addr[31:2]];
        selected_byte = word >> (test_addr[1:0] * 8);
        selected_half = test_addr[1] ? word[31:16] : word[15:0];

        case (test_funct3)
            LOAD_BYTE: return {{24{selected_byte[7]}}, selected_byte};
            LOAD_HALF: return {{16{selected_half[15]}}, selected_half};
            LOAD_WORD: return word;
            LOAD_BYTE_U: return {24'b0, selected_byte};
            LOAD_HALF_U: return {16'b0, selected_half};
            default: return 32'b0;
        endcase
    endfunction

    task automatic update_model(
        input logic [31:0] test_addr,
        input logic [31:0] test_data,
        input logic [2:0] test_funct3
    );
        case (test_funct3)
            STORE_BYTE: begin
                case (test_addr[1:0])
                    2'd0: model[test_addr[31:2]][7:0] = test_data[7:0];
                    2'd1: model[test_addr[31:2]][15:8] = test_data[7:0];
                    2'd2: model[test_addr[31:2]][23:16] = test_data[7:0];
                    2'd3: model[test_addr[31:2]][31:24] = test_data[7:0];
                endcase
            end

            STORE_HALF: begin
                if (test_addr[1]) begin
                    model[test_addr[31:2]][31:16] = test_data[15:0];
                end else begin
                    model[test_addr[31:2]][15:0] = test_data[15:0];
                end
            end

            STORE_WORD: model[test_addr[31:2]] = test_data;
            default: begin end
        endcase
    endtask

    task automatic check_read(
        input logic [31:0] test_addr,
        input logic [2:0] test_funct3,
        input string test_name
    );
        logic [31:0] expected;

        addr = test_addr;
        funct3 = test_funct3;
        mem_read = 1'b1;
        mem_write = 1'b0;
        expected = model_read(test_addr, test_funct3);
        #1;

        if (access_fault) begin
            $error("%s: unexpected access fault", test_name);
            errors++;
        end

        if (rd_data !== expected) begin
            $error(
                "%s: addr=%h funct3=%b expected=%h actual=%h",
                test_name,
                test_addr,
                test_funct3,
                expected,
                rd_data
            );
            errors++;
        end

        operation_hits[test_funct3]++;
        byte_lane_hits[test_addr[1:0]]++;
    endtask

    task automatic perform_write(
        input logic [31:0] test_addr,
        input logic [31:0] test_data,
        input logic [2:0] test_funct3
    );
        @(negedge clk);
        addr <= test_addr;
        wr_data <= test_data;
        funct3 <= test_funct3;
        mem_read <= 1'b0;
        mem_write <= 1'b1;
        #1;

        if (access_fault) begin
            $error("Unexpected write fault: addr=%h funct3=%b", test_addr, test_funct3);
            errors++;
        end

        @(posedge clk);
        update_model(test_addr, test_data, test_funct3);
        @(negedge clk);
        mem_write <= 1'b0;
        operation_hits[test_funct3]++;
        byte_lane_hits[test_addr[1:0]]++;
    endtask

    task automatic check_fault(
        input logic [31:0] test_addr,
        input logic [2:0] test_funct3,
        input logic test_mem_read,
        input logic test_mem_write,
        input string test_name
    );
        logic [31:0] memory_before;

        memory_before = model[0];
        @(negedge clk);
        addr <= test_addr;
        wr_data <= 32'hdead_beef;
        funct3 <= test_funct3;
        mem_read <= test_mem_read;
        mem_write <= test_mem_write;
        #1;

        if (!access_fault) begin
            $error("%s: expected access fault", test_name);
            errors++;
        end

        if (rd_data !== 32'b0) begin
            $error("%s: faulting read did not return zero", test_name);
            errors++;
        end

        @(posedge clk);
        @(negedge clk);
        if (model[0] !== memory_before || DUT.mem[0] !== memory_before) begin
            $error("%s: faulting request changed memory", test_name);
            errors++;
        end

        mem_read <= 1'b0;
        mem_write <= 1'b0;
        fault_hits++;
    endtask

    function automatic logic [31:0] aligned_address(
        input logic [2:0] test_funct3
    );
        logic [31:0] result;

        result = $urandom_range(0, DEPTH - 1) * 4;
        case (test_funct3[1:0])
            2'b00: result += $urandom_range(0, 3);
            2'b01: result += $urandom_range(0, 1) * 2;
            default: begin end
        endcase
        return result;
    endfunction

    initial begin : provide_stimulus
        for (int i = 0; i < DEPTH; i++) begin
            model[i] = '0;
        end

        addr <= '0;
        wr_data <= '0;
        funct3 <= LOAD_WORD;
        mem_read <= 1'b0;
        mem_write <= 1'b0;

        perform_write(32'd0, 32'h80ff_7f01, STORE_WORD);
        check_read(32'd0, LOAD_BYTE, "LB lane 0");
        check_read(32'd1, LOAD_BYTE, "LB lane 1");
        check_read(32'd2, LOAD_BYTE, "LB lane 2");
        check_read(32'd3, LOAD_BYTE, "LB lane 3");
        check_read(32'd0, LOAD_BYTE_U, "LBU lane 0");
        check_read(32'd3, LOAD_BYTE_U, "LBU lane 3");
        check_read(32'd0, LOAD_HALF, "LH lower");
        check_read(32'd2, LOAD_HALF, "LH upper");
        check_read(32'd0, LOAD_HALF_U, "LHU lower");
        check_read(32'd2, LOAD_HALF_U, "LHU upper");
        check_read(32'd0, LOAD_WORD, "LW");

        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            logic [31:0] random_addr;
            logic [31:0] random_data;
            logic [2:0] random_funct3;

            random_data = $urandom;

            if ($urandom_range(0, 1)) begin
                case ($urandom_range(0, 2))
                    0: random_funct3 = STORE_BYTE;
                    1: random_funct3 = STORE_HALF;
                    default: random_funct3 = STORE_WORD;
                endcase
                random_addr = aligned_address(random_funct3);
                perform_write(random_addr, random_data, random_funct3);
            end else begin
                case ($urandom_range(0, 4))
                    0: random_funct3 = LOAD_BYTE;
                    1: random_funct3 = LOAD_HALF;
                    2: random_funct3 = LOAD_WORD;
                    3: random_funct3 = LOAD_BYTE_U;
                    default: random_funct3 = LOAD_HALF_U;
                endcase
                random_addr = aligned_address(random_funct3);
                check_read(
                    random_addr,
                    random_funct3,
                    $sformatf("random data-memory read %0d", i)
                );
            end
        end

        check_fault(32'd1, LOAD_HALF, 1'b1, 1'b0, "misaligned halfword load");
        check_fault(32'd2, LOAD_WORD, 1'b1, 1'b0, "misaligned word load");
        check_fault(32'd1, STORE_HALF, 1'b0, 1'b1, "misaligned halfword store");
        check_fault(32'd2, STORE_WORD, 1'b0, 1'b1, "misaligned word store");
        check_fault(DEPTH * 4, LOAD_WORD, 1'b1, 1'b0, "out-of-range load");
        check_fault(DEPTH * 4, STORE_WORD, 1'b0, 1'b1, "out-of-range store");
        check_fault(32'd0, 3'b011, 1'b1, 1'b0, "invalid load encoding");
        check_fault(32'd0, STORE_WORD, 1'b1, 1'b1, "simultaneous read and write");

        for (int lane = 0; lane < 4; lane++) begin
            if (byte_lane_hits[lane] == 0) begin
                $error("Missing data-memory byte-lane coverage %0d", lane);
                errors++;
            end
        end

        foreach (operation_hits[op]) begin
            if (((op == LOAD_BYTE) ||
                 (op == LOAD_HALF) ||
                 (op == LOAD_WORD) ||
                 (op == LOAD_BYTE_U) ||
                 (op == LOAD_HALF_U)) &&
                (operation_hits[op] == 0)) begin
                $error("Missing data-memory funct3 coverage %0d", op);
                errors++;
            end
        end

        if (fault_hits != 8) begin
            $error("Expected 8 directed fault cases, observed %0d", fault_hits);
            errors++;
        end

        if (errors == 0) begin
            $display("PASS: dmem_tb");
        end else begin
            $fatal(1, "FAIL: dmem_tb completed with %0d error(s)", errors);
        end

        disable generate_clock;
    end
endmodule

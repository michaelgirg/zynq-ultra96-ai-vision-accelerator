import rv32i_pkg::*;

module load_use_hazard_unit_tb;
    logic if_id_valid;
    logic [4:0] if_id_rs1_addr;
    logic [4:0] if_id_rs2_addr;
    id_ex_t id_ex_data;
    logic stall_pc;
    logic stall_if_id;
    logic flush_id_ex;
    int errors;

    load_use_hazard_unit dut (
        .if_id_valid    (if_id_valid),
        .if_id_rs1_addr (if_id_rs1_addr),
        .if_id_rs2_addr (if_id_rs2_addr),
        .id_ex_data     (id_ex_data),
        .stall_pc       (stall_pc),
        .stall_if_id    (stall_if_id),
        .flush_id_ex    (flush_id_ex)
    );

    task automatic clear_inputs();
        if_id_valid = 1'b0;
        if_id_rs1_addr = 5'd0;
        if_id_rs2_addr = 5'd0;
        id_ex_data = ID_EX_BUBBLE;
    endtask

    task automatic make_ex_load(input logic [4:0] rd_addr);
        id_ex_data = ID_EX_BUBBLE;
        id_ex_data.valid = 1'b1;
        id_ex_data.mem_read = 1'b1;
        id_ex_data.reg_write = 1'b1;
        id_ex_data.rd_addr = rd_addr;
    endtask

    task automatic make_ex_alu_write(input logic [4:0] rd_addr);
        id_ex_data = ID_EX_BUBBLE;
        id_ex_data.valid = 1'b1;
        id_ex_data.mem_read = 1'b0;
        id_ex_data.reg_write = 1'b1;
        id_ex_data.rd_addr = rd_addr;
    endtask

    task automatic check(
        input string name,
        input logic expected_stall_pc,
        input logic expected_stall_if_id,
        input logic expected_flush_id_ex
    );
        #1;
        if ((stall_pc !== expected_stall_pc) ||
            (stall_if_id !== expected_stall_if_id) ||
            (flush_id_ex !== expected_flush_id_ex)) begin
            $error("FAIL %s: stall_pc=%b expected=%b, stall_if_id=%b expected=%b, flush_id_ex=%b expected=%b",
                   name,
                   stall_pc, expected_stall_pc,
                   stall_if_id, expected_stall_if_id,
                   flush_id_ex, expected_flush_id_ex);
            errors++;
        end
    endtask

    task automatic expect_no_hazard(input string name);
        check(name, 1'b0, 1'b0, 1'b0);
    endtask

    task automatic expect_hazard(input string name);
        check(name, 1'b1, 1'b1, 1'b1);
    endtask

    initial begin
        errors = 0;

        clear_inputs();
        expect_no_hazard("all defaults");

        clear_inputs();
        if_id_valid = 1'b1;
        if_id_rs1_addr = 5'd5;
        make_ex_load(5'd5);
        expect_hazard("load-use hazard on rs1");

        clear_inputs();
        if_id_valid = 1'b1;
        if_id_rs2_addr = 5'd5;
        make_ex_load(5'd5);
        expect_hazard("load-use hazard on rs2");

        clear_inputs();
        if_id_valid = 1'b1;
        if_id_rs1_addr = 5'd8;
        if_id_rs2_addr = 5'd8;
        make_ex_load(5'd8);
        expect_hazard("load-use hazard on both source registers");

        clear_inputs();
        if_id_valid = 1'b0;
        if_id_rs1_addr = 5'd5;
        make_ex_load(5'd5);
        expect_no_hazard("decode instruction invalid");

        clear_inputs();
        if_id_valid = 1'b1;
        if_id_rs1_addr = 5'd5;
        make_ex_load(5'd5);
        id_ex_data.valid = 1'b0;
        expect_no_hazard("execute instruction invalid");

        clear_inputs();
        if_id_valid = 1'b1;
        if_id_rs1_addr = 5'd5;
        make_ex_alu_write(5'd5);
        expect_no_hazard("ALU producer can be handled by forwarding");

        clear_inputs();
        if_id_valid = 1'b1;
        if_id_rs1_addr = 5'd5;
        make_ex_load(5'd5);
        id_ex_data.reg_write = 1'b0;
        expect_no_hazard("load with no register write");

        clear_inputs();
        if_id_valid = 1'b1;
        if_id_rs1_addr = 5'd0;
        if_id_rs2_addr = 5'd0;
        make_ex_load(5'd0);
        expect_no_hazard("x0 is ignored");

        clear_inputs();
        if_id_valid = 1'b1;
        if_id_rs1_addr = 5'd0;
        if_id_rs2_addr = 5'd7;
        make_ex_load(5'd0);
        expect_no_hazard("decode rs1 x0 does not match real load destination");

        clear_inputs();
        if_id_valid = 1'b1;
        if_id_rs1_addr = 5'd6;
        if_id_rs2_addr = 5'd7;
        make_ex_load(5'd5);
        expect_no_hazard("valid load but no source match");

        clear_inputs();
        if_id_valid = 1'b1;
        if_id_rs1_addr = 5'd5;
        if_id_rs2_addr = 5'd7;
        make_ex_load(5'd7);
        expect_hazard("rs2 match still hazards when rs1 does not match");

        clear_inputs();
        if_id_valid = 1'b1;
        if_id_rs1_addr = 5'd5;
        if_id_rs2_addr = 5'd7;
        make_ex_load(5'd5);
        expect_hazard("rs1 match still hazards when rs2 does not match");

        if (errors == 0) $display("PASS: load_use_hazard_unit_tb");
        else $fatal(1, "FAIL: load_use_hazard_unit_tb had %0d errors", errors);
    end

endmodule

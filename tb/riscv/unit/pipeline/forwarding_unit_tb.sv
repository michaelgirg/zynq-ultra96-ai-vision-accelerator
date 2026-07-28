import rv32i_pkg::*;

module forwarding_unit_tb;
    localparam logic [1:0] FWD_REG    = 2'b00;
    localparam logic [1:0] FWD_MEM_WB = 2'b01;
    localparam logic [1:0] FWD_EX_MEM = 2'b10;

    logic [4:0] rs1_addr;
    logic [4:0] rs2_addr;
    ex_mem_t ex_mem_data;
    mem_wb_t mem_wb_data;
    logic [1:0] forward_a;
    logic [1:0] forward_b;
    int errors;

    forwarding_unit dut (
        .rs1_addr    (rs1_addr),
        .rs2_addr    (rs2_addr),
        .ex_mem_data (ex_mem_data),
        .mem_wb_data (mem_wb_data),
        .forward_a   (forward_a),
        .forward_b   (forward_b)
    );

    task automatic reset_inputs();
        rs1_addr = 5'd0;
        rs2_addr = 5'd0;
        ex_mem_data = EX_MEM_BUBBLE;
        mem_wb_data = MEM_WB_BUBBLE;
    endtask

    task automatic check(
        input string name,
        input logic [1:0] expected_a,
        input logic [1:0] expected_b
    );
        #1;
        if ((forward_a !== expected_a) || (forward_b !== expected_b)) begin
            $error("FAIL %s: forward_a=%b expected=%b, forward_b=%b expected=%b",
                   name, forward_a, expected_a, forward_b, expected_b);
            errors++;
        end
    endtask

    initial begin
        errors = 0;

        reset_inputs();
        rs1_addr = 5'd1;
        rs2_addr = 5'd2;
        check("no matching producers", FWD_REG, FWD_REG);

        reset_inputs();
        rs1_addr = 5'd5;
        rs2_addr = 5'd7;
        mem_wb_data.valid = 1'b1;
        mem_wb_data.reg_write = 1'b1;
        mem_wb_data.rd_addr = 5'd5;
        check("MEM/WB forwards rs1", FWD_MEM_WB, FWD_REG);

        reset_inputs();
        rs1_addr = 5'd5;
        rs2_addr = 5'd7;
        mem_wb_data.valid = 1'b1;
        mem_wb_data.reg_write = 1'b1;
        mem_wb_data.rd_addr = 5'd7;
        check("MEM/WB forwards rs2", FWD_REG, FWD_MEM_WB);

        reset_inputs();
        rs1_addr = 5'd3;
        rs2_addr = 5'd3;
        mem_wb_data.valid = 1'b1;
        mem_wb_data.reg_write = 1'b1;
        mem_wb_data.rd_addr = 5'd3;
        ex_mem_data.valid = 1'b1;
        ex_mem_data.reg_write = 1'b1;
        ex_mem_data.rd_addr = 5'd3;
        check("EX/MEM priority over MEM/WB", FWD_EX_MEM, FWD_EX_MEM);

        reset_inputs();
        rs1_addr = 5'd0;
        rs2_addr = 5'd0;
        ex_mem_data.valid = 1'b1;
        ex_mem_data.reg_write = 1'b1;
        ex_mem_data.rd_addr = 5'd0;
        mem_wb_data.valid = 1'b1;
        mem_wb_data.reg_write = 1'b1;
        mem_wb_data.rd_addr = 5'd0;
        check("never forward x0", FWD_REG, FWD_REG);

        reset_inputs();
        rs1_addr = 5'd9;
        rs2_addr = 5'd10;
        ex_mem_data.valid = 1'b0;
        ex_mem_data.reg_write = 1'b1;
        ex_mem_data.rd_addr = 5'd9;
        mem_wb_data.valid = 1'b1;
        mem_wb_data.reg_write = 1'b0;
        mem_wb_data.rd_addr = 5'd10;
        check("invalid or no reg_write does not forward", FWD_REG, FWD_REG);

        reset_inputs();
        rs1_addr = 5'd11;
        rs2_addr = 5'd12;
        ex_mem_data.valid = 1'b1;
        ex_mem_data.reg_write = 1'b1;
        ex_mem_data.mem_read = 1'b1;
        ex_mem_data.rd_addr = 5'd11;
        mem_wb_data.valid = 1'b1;
        mem_wb_data.reg_write = 1'b1;
        mem_wb_data.rd_addr = 5'd12;
        check("load cannot forward from EX/MEM", FWD_REG, FWD_MEM_WB);

        if (errors == 0) begin
            $display("PASS: forwarding_unit_tb");
        end else begin
            $fatal(1, "FAIL: forwarding_unit_tb had %0d errors", errors);
        end
    end

endmodule

import rv32i_pkg::*;

module ex_mem_reg_tb;
    logic clk;
    logic rst;
    logic en;
    logic flush;
    ex_mem_t data;
    ex_mem_t data_o;
    int errors;

    ex_mem_reg dut (
        .clk    (clk),
        .rst    (rst),
        .en     (en),
        .flush  (flush),
        .data   (data),
        .data_o (data_o)
    );

    function automatic ex_mem_t make_entry(input logic [31:0] pc, input logic [4:0] rd_addr);
        ex_mem_t entry;

        entry = EX_MEM_BUBBLE;
        entry.valid = 1'b1;
        entry.pc = pc;
        entry.pc_plus_four = pc + 32'd4;
        entry.alu_result = 32'hABCD_0000 | pc[15:0];
        entry.store_data = 32'h1234_0000 | pc[15:0];
        entry.rd_addr = rd_addr;
        entry.wb_sel = WB_ALU;
        entry.mem_size = MEM_WORD;
        entry.reg_write = 1'b1;

        return entry;
    endfunction

    task automatic tick();
        #5 clk = 1'b1;
        #1;
        #4 clk = 1'b0;
        #1;
    endtask

    task automatic check(input string name, input ex_mem_t expected);
        if (data_o !== expected) begin
            $error("FAIL %s: data_o=0x%0h expected=0x%0h", name, data_o, expected);
            errors++;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        en = 1'b1;
        flush = 1'b0;
        data = make_entry(32'h0000_1000, 5'd5);
        errors = 0;

        tick();
        check("reset inserts bubble", EX_MEM_BUBBLE);

        rst = 1'b0;
        en = 1'b1;
        data = make_entry(32'h0000_2000, 5'd6);
        tick();
        check("enable advances data", data);

        en = 1'b0;
        data = make_entry(32'h0000_3000, 5'd7);
        tick();
        check("stall holds previous data", make_entry(32'h0000_2000, 5'd6));

        en = 1'b1;
        flush = 1'b1;
        data = make_entry(32'h0000_4000, 5'd8);
        tick();
        check("flush inserts bubble", EX_MEM_BUBBLE);

        rst = 1'b1;
        flush = 1'b1;
        data = make_entry(32'h0000_5000, 5'd9);
        tick();
        check("reset and flush insert bubble", EX_MEM_BUBBLE);

        if (errors == 0) begin
            $display("PASS: ex_mem_reg_tb");
        end else begin
            $fatal(1, "FAIL: ex_mem_reg_tb had %0d errors", errors);
        end
    end

endmodule

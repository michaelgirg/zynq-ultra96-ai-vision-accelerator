import rv32i_pkg::*;

module mem_wb_reg_tb;
    logic clk;
    logic rst;
    logic flush;
    mem_wb_t d;
    mem_wb_t q;
    int errors;

    mem_wb_reg dut (
        .clk   (clk),
        .rst   (rst),
        .flush (flush),
        .d     (d),
        .q     (q)
    );

    function automatic mem_wb_t make_entry(input logic [31:0] pc, input logic [4:0] rd_addr);
        mem_wb_t entry;

        entry = MEM_WB_BUBBLE;
        entry.valid = 1'b1;
        entry.pc = pc;
        entry.pc_plus_four = pc + 32'd4;
        entry.alu_result = 32'hCAFE_0000 | pc[15:0];
        entry.memory_read_data = 32'hBEEF_0000 | pc[15:0];
        entry.rd_addr = rd_addr;
        entry.wb_sel = WB_MEM;
        entry.reg_write = 1'b1;

        return entry;
    endfunction

    task automatic tick();
        #5 clk = 1'b1;
        #1;
        #4 clk = 1'b0;
        #1;
    endtask

    task automatic check(input string name, input mem_wb_t expected);
        if (q !== expected) begin
            $error("FAIL %s: q=0x%0h expected=0x%0h", name, q, expected);
            errors++;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b0;
        flush = 1'b0;
        d = make_entry(32'h0000_1000, 5'd5);
        errors = 0;

        rst = 1'b1;
        tick();
        check("sync reset inserts bubble", MEM_WB_BUBBLE);

        rst = 1'b0;
        d = make_entry(32'h0000_2000, 5'd6);
        tick();
        check("normal advance loads memory result", d);

        flush = 1'b1;
        d = make_entry(32'h0000_3000, 5'd7);
        tick();
        check("flush inserts bubble", MEM_WB_BUBBLE);

        flush = 1'b0;
        d = make_entry(32'h0000_4000, 5'd8);
        tick();
        check("advance after flush", d);

        rst = 1'b1;
        tick();
        check("sync reset beats current contents", MEM_WB_BUBBLE);

        if (errors == 0) $display("PASS: mem_wb_reg_tb");
        else $fatal(1, "FAIL: mem_wb_reg_tb had %0d errors", errors);
    end

endmodule

import rv32i_pkg::*;

module if_id_reg_tb;
    logic clk;
    logic rst;
    logic stall;
    logic flush;
    if_id_t d;
    if_id_t q;
    int errors;

    if_id_reg dut (
        .clk   (clk),
        .rst   (rst),
        .stall (stall),
        .flush (flush),
        .d     (d),
        .q     (q)
    );

    function automatic if_id_t make_entry(input logic [31:0] pc, input logic [31:0] instruction);
        if_id_t entry;

        entry = IF_ID_BUBBLE;
        entry.valid = 1'b1;
        entry.pc = pc;
        entry.instruction = instruction;
        entry.instruction_fault = 1'b0;

        return entry;
    endfunction

    task automatic tick();
        #5 clk = 1'b1;
        #1;
        #4 clk = 1'b0;
        #1;
    endtask

    task automatic check(input string name, input if_id_t expected);
        if (q !== expected) begin
            $error("FAIL %s: q=0x%0h expected=0x%0h", name, q, expected);
            errors++;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b0;
        stall = 1'b0;
        flush = 1'b0;
        d = make_entry(32'h0000_1000, 32'h0010_0093);
        errors = 0;

        rst = 1'b1;
        tick();
        check("sync reset inserts bubble", IF_ID_BUBBLE);

        rst = 1'b0;
        d = make_entry(32'h0000_2000, 32'h0020_0113);
        tick();
        check("normal advance loads fetch entry", d);

        stall = 1'b1;
        d = make_entry(32'h0000_3000, 32'h0030_0193);
        tick();
        check("stall holds previous entry", make_entry(32'h0000_2000, 32'h0020_0113));

        flush = 1'b1;
        d = make_entry(32'h0000_4000, 32'h0040_0213);
        tick();
        check("flush beats stall and inserts bubble", IF_ID_BUBBLE);

        stall = 1'b0;
        flush = 1'b0;
        d = make_entry(32'h0000_5000, 32'h0050_0293);
        tick();
        check("advance after flush", d);

        rst = 1'b1;
        tick();
        check("sync reset beats current contents", IF_ID_BUBBLE);

        if (errors == 0) $display("PASS: if_id_reg_tb");
        else $fatal(1, "FAIL: if_id_reg_tb had %0d errors", errors);
    end

endmodule

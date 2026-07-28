module pipeline_control_tb;
    logic ex_redirect;
    logic [31:0] ex_target;
    logic load_use_stall;
    logic muldiv_stall;
    logic mem_stall;
    logic if_stall;
    logic trap_req;
    logic [31:0] trap_target;
    logic pc_redirect;
    logic [31:0] pc_target;
    logic pc_stall;
    logic stall_if_id;
    logic flush_if_id;
    logic flush_id_ex;
    logic stall_id_ex;
    logic stall_ex_mem;
    logic flush_ex_mem;
    int errors;

    pipeline_control dut (
        .ex_redirect   (ex_redirect),
        .ex_target     (ex_target),
        .load_use_stall(load_use_stall),
        .muldiv_stall  (muldiv_stall),
        .mem_stall     (mem_stall),
        .if_stall      (if_stall),
        .trap_req      (trap_req),
        .trap_target   (trap_target),
        .pc_redirect   (pc_redirect),
        .pc_target     (pc_target),
        .pc_stall      (pc_stall),
        .stall_if_id   (stall_if_id),
        .flush_if_id   (flush_if_id),
        .flush_id_ex   (flush_id_ex),
        .stall_id_ex   (stall_id_ex),
        .stall_ex_mem  (stall_ex_mem),
        .flush_ex_mem  (flush_ex_mem)
    );

    task automatic clear_inputs();
        ex_redirect = 1'b0;
        ex_target = 32'h0000_0000;
        load_use_stall = 1'b0;
        muldiv_stall = 1'b0;
        mem_stall = 1'b0;
        if_stall = 1'b0;
        trap_req = 1'b0;
        trap_target = 32'h0000_0000;
    endtask

    task automatic check(
        input string name,
        input logic expected_pc_redirect,
        input logic [31:0] expected_pc_target,
        input logic expected_pc_stall,
        input logic expected_stall_if_id,
        input logic expected_flush_if_id,
        input logic expected_flush_id_ex,
        input logic expected_stall_id_ex,
        input logic expected_stall_ex_mem,
        input logic expected_flush_ex_mem
    );
        #1;
        if ((pc_redirect !== expected_pc_redirect) ||
            (pc_target !== expected_pc_target) ||
            (pc_stall !== expected_pc_stall) ||
            (stall_if_id !== expected_stall_if_id) ||
            (flush_if_id !== expected_flush_if_id) ||
            (flush_id_ex !== expected_flush_id_ex) ||
            (stall_id_ex !== expected_stall_id_ex) ||
            (stall_ex_mem !== expected_stall_ex_mem) ||
            (flush_ex_mem !== expected_flush_ex_mem)) begin
            $error("FAIL %s: redirect=%b/%b target=0x%08h/0x%08h pc_stall=%b/%b stall_if_id=%b/%b flush_if_id=%b/%b flush_id_ex=%b/%b stall_id_ex=%b/%b stall_ex_mem=%b/%b flush_ex_mem=%b/%b",
                   name,
                   pc_redirect, expected_pc_redirect,
                   pc_target, expected_pc_target,
                   pc_stall, expected_pc_stall,
                   stall_if_id, expected_stall_if_id,
                   flush_if_id, expected_flush_if_id,
                   flush_id_ex, expected_flush_id_ex,
                   stall_id_ex, expected_stall_id_ex,
                   stall_ex_mem, expected_stall_ex_mem,
                   flush_ex_mem, expected_flush_ex_mem);
            errors++;
        end
    endtask

    initial begin
        errors = 0;

        //                                       redir  target          pc_stl if_id  fl_if  fl_id  st_id  st_exm fl_exm
        clear_inputs();
        check("normal advance",                  1'b0, 32'h0000_0000,   1'b0,  1'b0,  1'b0,  1'b0,  1'b0,  1'b0,  1'b0);

        clear_inputs();
        load_use_stall = 1'b1;
        check("load-use stall",                  1'b0, 32'h0000_0000,   1'b1,  1'b1,  1'b0,  1'b1,  1'b0,  1'b0,  1'b0);

        clear_inputs();
        muldiv_stall = 1'b1;
        check("muldiv stall",                    1'b0, 32'h0000_0000,   1'b1,  1'b1,  1'b0,  1'b0,  1'b1,  1'b0,  1'b1);

        clear_inputs();
        mem_stall = 1'b1;
        check("MEM stall",                       1'b0, 32'h0000_0000,   1'b1,  1'b1,  1'b0,  1'b0,  1'b1,  1'b1,  1'b0);

        clear_inputs();
        if_stall = 1'b1;
        check("I-cache stall",                    1'b0, 32'h0000_0000,   1'b1,  1'b1,  1'b0,  1'b0,  1'b0,  1'b0,  1'b0);

        clear_inputs();
        ex_redirect = 1'b1;
        ex_target = 32'h0000_4000;
        check("EX redirect",                     1'b1, 32'h0000_4000,   1'b0,  1'b0,  1'b1,  1'b1,  1'b0,  1'b0,  1'b0);

        clear_inputs();
        trap_req = 1'b1;
        trap_target = 32'h0000_0080;
        check("trap redirect",                   1'b1, 32'h0000_0080,   1'b0,  1'b0,  1'b1,  1'b1,  1'b0,  1'b0,  1'b0);

        clear_inputs();
        ex_redirect = 1'b1;
        ex_target = 32'h0000_4000;
        load_use_stall = 1'b1;
        check("redirect beats load-use stall",   1'b1, 32'h0000_4000,   1'b0,  1'b0,  1'b1,  1'b1,  1'b0,  1'b0,  1'b0);

        clear_inputs();
        load_use_stall = 1'b1;
        muldiv_stall = 1'b1;
        check("load-use beats muldiv stall",     1'b0, 32'h0000_0000,   1'b1,  1'b1,  1'b0,  1'b1,  1'b0,  1'b0,  1'b0);

        clear_inputs();
        ex_redirect = 1'b1;
        ex_target = 32'h0000_4000;
        muldiv_stall = 1'b1;
        // MUL/DIV and redirects cannot describe the same legal ID/EX entry.
        // The independent bubble output remains asserted for fail-safe handling
        // of this artificial input combination.
        check("redirect with impossible muldiv", 1'b1, 32'h0000_4000,   1'b0,  1'b0,  1'b1,  1'b1,  1'b0,  1'b0,  1'b1);

        clear_inputs();
        ex_redirect = 1'b1;
        ex_target = 32'h0000_4000;
        if_stall = 1'b1;
        check("redirect beats I-cache stall",     1'b1, 32'h0000_4000,   1'b0,  1'b0,  1'b1,  1'b1,  1'b0,  1'b0,  1'b0);

        clear_inputs();
        muldiv_stall = 1'b1;
        if_stall = 1'b1;
        check("muldiv beats I-cache stall",       1'b0, 32'h0000_0000,   1'b1,  1'b1,  1'b0,  1'b0,  1'b1,  1'b0,  1'b1);

        clear_inputs();
        mem_stall = 1'b1;
        ex_redirect = 1'b1;
        ex_target = 32'h0000_4000;
        muldiv_stall = 1'b1;
        check("MEM stall holds younger EX work", 1'b0, 32'h0000_0000,   1'b1,  1'b1,  1'b0,  1'b0,  1'b1,  1'b1,  1'b0);

        clear_inputs();
        trap_req = 1'b1;
        trap_target = 32'h0000_0080;
        ex_redirect = 1'b1;
        ex_target = 32'h0000_4000;
        load_use_stall = 1'b1;
        mem_stall = 1'b1;
        check("trap beats MEM and redirect",      1'b1, 32'h0000_0080,  1'b0,  1'b0,  1'b1,  1'b1,  1'b0,  1'b0,  1'b0);

        clear_inputs();
        ex_redirect = 1'b0;
        ex_target = 32'h1111_2222;
        trap_req = 1'b0;
        trap_target = 32'h3333_4444;
        check("inactive targets do not leak",    1'b0, 32'h0000_0000,   1'b0,  1'b0,  1'b0,  1'b0,  1'b0,  1'b0,  1'b0);

        if (errors == 0) $display("PASS: pipeline_control_tb");
        else $fatal(1, "FAIL: pipeline_control_tb had %0d errors", errors);
    end

endmodule

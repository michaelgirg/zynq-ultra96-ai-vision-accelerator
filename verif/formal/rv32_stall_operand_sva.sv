// Simulation assertions, not part of the synthesizable file list.
module rv32_stall_operand_sva (
    input logic clk_i, rst_i, stall_id_ex, flush_id_ex,
    input wire rv32i_pkg::id_ex_t id_ex_q,
    input logic [31:0] forwarded_rs1_data, forwarded_rs2_data
);
    rv32i_pkg::id_ex_t metadata;
    always_comb begin
        metadata = id_ex_q;
        metadata.rs1_data = 0;
        metadata.rs2_data = 0;
    end
    assert property (@(posedge clk_i) disable iff (rst_i)
        stall_id_ex && !flush_id_ex |=> $stable(metadata));
    assert property (@(posedge clk_i) disable iff (rst_i)
        stall_id_ex && !flush_id_ex |=> id_ex_q.rs1_data == $past(forwarded_rs1_data));
    assert property (@(posedge clk_i) disable iff (rst_i)
        stall_id_ex && !flush_id_ex |=> id_ex_q.rs2_data == $past(forwarded_rs2_data));
endmodule

bind core_pipeline rv32_stall_operand_sva stall_operand_checks (
    .clk_i, .rst_i, .stall_id_ex, .flush_id_ex, .id_ex_q,
    .forwarded_rs1_data, .forwarded_rs2_data
);

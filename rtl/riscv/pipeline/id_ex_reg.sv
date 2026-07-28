import rv32i_pkg::*;

// ID/EX pipeline register.
//
// This register separates the Instruction Decode (ID) stage
// from the Execute (EX) stage.
//
// At every rising clk edge it does 3 things:
//
// 1. Reset/flush: clears the reg to a bubble.
// 2. Enable: advances the decoded instruction into the EX stage.
// 3. Otherwise: holds its current contents during a pipeline stall.
//
// A bubble inserts an empty cycle in front of a waiting instruction,
// allowing the earlier instruction enough time to finish.
//
// In this case we have lw producing x5, and add is waiting for x5 because
// the load has not finished yet:
//
// lw  x5, 0(x1)
// add x6, x5, x2
//
// The flow looks like this:
//
// lw -> bubble -> add
//
// This is one reason OOO exists: an out-of-order core can sometimes do other
// independent work instead of wasting the bubble cycle.

module id_ex_reg (
    input logic clk,
    input logic rst,
    input logic en,
    input logic flush,

    input var id_ex_t data,  // Info produced from the Decode stage.

    output var id_ex_t data_o  // Registered info sent into the Execute stage.
);

    always_ff @(posedge clk) begin
        // rst or flush removes the current instruction by inserting a bubble.
        if (rst || flush) data_o <= ID_EX_BUBBLE;

        // Advance the decoded instruction when the pipeline is enabled.
        else if (en) data_o <= data;

        // Otherwise, data_o holds its current value during a stall.
    end

endmodule


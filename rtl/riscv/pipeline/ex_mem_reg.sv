import rv32i_pkg::*;

// EX/MEM pipeline register.
//
// This register separates the Execute (EX) stage from the Memory (MEM) stage.
//
// It stores information calculated during EX:
// - ALU result
// - Store data
// - Destination register
// - Memory control signals
// - Register writeback controls
//
// At each rising clock edge:
// - Reset or flush inserts a bubble.
// - Enable advances the instruction into the Memory stage.
// - Otherwise, the current contents are held during a stall.

module ex_mem_reg (
    input logic clk,
    input logic rst,
    input logic en,
    input logic flush,

    input var ex_mem_t data,  // Results and control signals from the EX stage.

    output var ex_mem_t data_o  // Registered information sent into MEM.
);

    always_ff @(posedge clk) begin
        // Reset or flush removes the current instruction by inserting a bubble.
        // A bubble has valid = 0 and cannot change memory or the register file.
        if (rst || flush) data_o <= EX_MEM_BUBBLE;

        // When enabled, advance the EX results into the MEM stage.
        else if (en) data_o <= data;

        // When en = 0, keep the current contents until the pipeline advances.
    end

endmodule

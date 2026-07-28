  // =============================================================================
// mem_wb_reg.sv  --  MEM/WB pipeline register
// Owner: control/memory section
// -----------------------------------------------------------------------------
// Final stage register: hands the resolved writeback value + destination to WB.
// No stall input: in a classic 5-stage with single-cycle memory the back end
// always drains, so load-use stalls never reach here. (Add a stall enable only
// when MEM becomes multi-cycle, e.g. a cache that can miss.)
// flush clears the slot so a trapped instruction does not commit to the regfile.
// =============================================================================
module mem_wb_reg
  import rv32i_pkg::*;
(
  input  logic    clk,
  input  logic    rst,
  input  logic    flush,   // trap squash: kill this writeback
  input  var mem_wb_t d,       // from MEM stage
  output var mem_wb_t q        // to WB stage
);
  always_ff @(posedge clk) begin
    if      (rst) q <= MEM_WB_BUBBLE;
    else if (flush)  q <= MEM_WB_BUBBLE;
    else             q <= d;
  end
endmodule

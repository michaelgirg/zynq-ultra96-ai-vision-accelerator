// =============================================================================
// if_id_reg.sv  --  IF/ID pipeline register
// Owner: control/memory section
// -----------------------------------------------------------------------------
// Carries fetched-instruction state from IF into ID.
// Priority of control inputs (highest first):
//   flush  : inject a NOP bubble (branch/jump/trap redirect squashes this slot)
//   stall  : hold current contents (load-use hazard freezes front of pipe)
//   else   : accept new fetch
// flush MUST outrank stall: when a redirect fires the same cycle a stall is
// requested, the held instruction is on the wrong path and has to die anyway.
// =============================================================================
module if_id_reg
  import rv32i_pkg::*;
(
  input  logic   clk,
  input  logic   rst,
  input  logic   stall,    // from pipeline_control (load-use)
  input  logic   flush,    // from pipeline_control (redirect/trap)
  input  var if_id_t d,        // from IF stage
  output var if_id_t q         // to ID stage
);
  always_ff @(posedge clk) begin
    if      (rst) q <= IF_ID_BUBBLE;
    else if (flush)  q <= IF_ID_BUBBLE;
    else if (stall)  q <= q;
    else             q <= d;
  end
endmodule

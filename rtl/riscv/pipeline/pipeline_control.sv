// =============================================================================
// pipeline_control.sv  --  control-hazard arbiter (branches, jumps, traps)
// Owner: control/memory section
// -----------------------------------------------------------------------------
// SINGLE owner of every pipeline-register enable/flush and of the PC redirect.
// The load_use_hazard_unit (partner's module) only *detects* the load-use case
// and raises load_use_stall; this module decides what the pipeline actually
// does with it. Keeping one driver per control signal avoids multi-driver
// conflicts at integration.
//
// Resolution model: branches and jumps are resolved in EX (predict-not-taken),
// so a taken transfer must squash the two instructions already fetched behind
// it (now sitting in ID and IF) -> flush BOTH if_id and id_ex. That is the
// standard 2-cycle penalty. (Resolving JAL in ID would cut it to 1 cycle; left
// as a later optimization.)
//
// Priority: trap > MEM stall > redirect > load-use > MUL/DIV > I-cache stall
//   - trap outranks a branch: an exception on the older instruction wins.
//   - a MEM stall holds the older EX/MEM instruction, so younger EX work cannot
//     advance or redirect until the cache transaction completes.
//   - redirects outrank front-end and EX-only stalls once MEM can advance.
// =============================================================================
module pipeline_control (
  // ---- control-transfer resolution (from EX / partner's branch logic) -------
  input  logic        ex_redirect,    // taken branch OR jal/jalr, resolved in EX
  input  logic [31:0] ex_target,      // redirect destination

  // ---- load-use hazard (from load_use_hazard_unit) --------------------------
  input  logic        load_use_stall,

  // ---- multi-cycle EX op (from muldiv_unit) ---------------------------------
  input  logic        muldiv_stall,   // MUL/DIV still computing in EX

  // ---- variable-latency MEM op (from D-cache integration) -------------------
  input  logic        mem_stall,      // request in EX/MEM has no response yet

  // ---- instruction-fetch miss ----------------------------------------------
  input  logic        if_stall,       // I-cache refill in flight

  // ---- trap / fault (v1 aggregate; refine with the CSR module) --------------
  input  logic        trap_req,       // exception detected this cycle
  input  logic [31:0] trap_target,    // mtvec base (stub until CSRs land)

  // ---- to PC / fetch --------------------------------------------------------
  output logic        pc_redirect,    // override sequential PC with pc_target
  output logic [31:0] pc_target,
  output logic        pc_stall,       // hold PC for a data, EX, or fetch stall

  // ---- to pipeline registers ------------------------------------------------
  output logic        stall_if_id,    // hold IF/ID  (load-use / muldiv)
  output logic        flush_if_id,    // bubble IF/ID (redirect/trap)
  output logic        flush_id_ex,    // bubble ID/EX (redirect / load-use bubble / trap)
  output logic        stall_id_ex,    // hold ID/EX  (muldiv: keep the op in EX)
  output logic        stall_ex_mem,   // hold EX/MEM (D-cache request in flight)
  output logic        flush_ex_mem    // bubble EX/MEM (muldiv: no result yet)
);
  // A legal ID/EX entry cannot be both a MUL/DIV instruction and a branch or
  // jump. Keep the EX/MEM bubble equation independent of ex_redirect so the
  // branch-forwarding path does not drive every EX/MEM register control pin.
  // Older traps, memory stalls, and load-use handling still keep their stated
  // priority and prevent the unfinished MUL/DIV result from advancing.
  assign flush_ex_mem = muldiv_stall &&
                        !trap_req &&
                        !mem_stall &&
                        !load_use_stall;

  always_comb begin
    // defaults: pipeline advances normally
    pc_redirect  = 1'b0;
    pc_target    = 32'b0;
    pc_stall     = 1'b0;
    stall_if_id  = 1'b0;
    flush_if_id  = 1'b0;
    flush_id_ex  = 1'b0;
    stall_id_ex  = 1'b0;
    stall_ex_mem = 1'b0;

    if (trap_req) begin
      // Redirect to the trap vector and squash the front of the pipe.
      // NOTE: capturing mepc/mcause and squashing the faulting instruction in
      // its own stage (precise exceptions) is the CSR follow-up; this is the
      // minimal redirect+flush hook.
      pc_redirect = 1'b1;
      pc_target   = trap_target;
      flush_if_id = 1'b1;
      flush_id_ex = 1'b1;
    end
    else if (mem_stall) begin
      // The oldest active instruction is waiting in MEM. Hold it in EX/MEM and
      // freeze every younger stage. MEM/WB is allowed to drain separately; the
      // cache integration must present a bubble there until a response arrives.
      pc_stall     = 1'b1;
      stall_if_id  = 1'b1;
      stall_id_ex  = 1'b1;
      stall_ex_mem = 1'b1;
    end
    else if (ex_redirect) begin
      // Taken branch/jump in EX: redirect fetch, kill the two wrong-path
      // instructions now in ID (-> flush_id_ex) and IF (-> flush_if_id).
      pc_redirect = 1'b1;
      pc_target   = ex_target;
      flush_if_id = 1'b1;
      flush_id_ex = 1'b1;
    end
    else if (load_use_stall) begin
      // Freeze PC + IF/ID, inject one bubble into EX.
      pc_stall    = 1'b1;
      stall_if_id = 1'b1;
      flush_id_ex = 1'b1;
    end
    else if (muldiv_stall) begin
      // Multi-cycle EX op (MUL/DIV) still computing: freeze the front of the
      // pipe and HOLD the op in ID/EX (do not bubble it), while draining
      // EX/MEM with a bubble so the unfinished result never advances to MEM.
      // (load_use_stall cannot be active here: EX holds a muldiv, not a load.)
      pc_stall     = 1'b1;
      stall_if_id  = 1'b1;
      stall_id_ex  = 1'b1;
    end
    else if (if_stall) begin
      // An instruction miss is younger than every instruction already in the
      // pipeline. Freeze only PC and IF/ID so older work can keep draining.
      // Redirects are intentionally above this case so a taken branch updates
      // PC even while an earlier wrong-path refill is still finishing.
      pc_stall    = 1'b1;
      stall_if_id = 1'b1;
    end
  end
endmodule

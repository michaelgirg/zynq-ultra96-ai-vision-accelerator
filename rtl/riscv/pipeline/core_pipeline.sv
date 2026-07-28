import rv32i_pkg::*;

// Five-stage pipelined RV32I core.
//
// Stages:
// IF  = Instruction Fetch
// ID  = Instruction Decode / Register Read
// EX  = Execute / Branch Decision
// MEM = Data Memory
// WB  = Writeback
//
// This top level wires together:
// - PC
// - instruction memory
// - decoder
// - immediate generator
// - register file
// - ALU
// - branch unit
// - data memory
// - pipeline registers
// - forwarding unit
// - load-use hazard unit
// - pipeline control unit

module core_pipeline #(
    parameter int IMEM_WORDS = 256,
    parameter int DMEM_WORDS = 1024,
    parameter string IMEM_HEX = "",
    parameter string DMEM_HEX = "",
    parameter int CACHE_LINE_WORDS = 4,
    parameter int ICACHE_NUM_SETS = 16,
    parameter int DCACHE_NUM_SETS = 16,
    parameter int DCACHE_NUM_WAYS = 2,
    parameter int IMEM_LATENCY = 15,
    parameter int DMEM_LATENCY = 15
) (
    input logic clk_i,
    input logic rst_i,

    output logic [31:0] current_pc_o,
    output logic [31:0] instruction_o,
    output logic        halted_o,
    output logic        illegal_instruction_o,
    output logic        instruction_fault_o,
    output logic        data_fault_o
);

    localparam int CACHE_LINE_BITS = 32 * CACHE_LINE_WORDS;

    // ------------------------------------------------------------------------
    // IF stage wires
    // ------------------------------------------------------------------------

    logic    [31:0] pc;
    // Preserve the incrementer output as a net boundary. This keeps Vivado
    // from absorbing the late branch-redirect mux into the PC + 4 carry chain.
    (* keep = "true" *) logic [31:0] pc_plus_four;
    logic    [31:0] next_pc;
    logic    [31:0] fetched_instruction;
    logic           imem_access_fault;
    logic           icache_resp_valid;
    logic           icache_stall;

    logic                         imem_req_ready;
    logic                         imem_req_valid;
    logic [31:0]                  imem_req_addr;
    logic                         imem_resp_valid;
    logic [CACHE_LINE_BITS-1:0]   imem_resp_rdata;
    logic                         imem_resp_fault;
    logic                         imem_resp_ready;

    if_id_t         if_id_d;
    if_id_t         if_id_q;

    // ------------------------------------------------------------------------
    // ID stage wires
    // ------------------------------------------------------------------------

    logic    [ 4:0] rs1_addr;
    logic    [ 4:0] rs2_addr;
    logic    [ 4:0] rd_addr;

    logic    [31:0] rs1_data;
    logic    [31:0] rs2_data;
    logic    [31:0] decode_rs1_data;
    logic    [31:0] decode_rs2_data;
    logic    [31:0] immediate;

    logic    [ 3:0] alu_op;
    logic    [ 2:0] imm_sel;
    logic    [ 2:0] branch_op;
    logic    [ 1:0] wb_sel;
    logic    [ 1:0] mem_size;
    muldiv_op_t     decode_muldiv_op;

    logic           reg_write;
    logic           alu_src_imm;
    logic           alu_src_pc;
    logic           mem_read;
    logic           mem_write;
    logic           load_unsigned;
    logic           jump;
    logic           jalr;
    logic           decode_is_muldiv;
    logic           halt;
    logic           illegal;

    id_ex_t         id_ex_d;
    id_ex_t         id_ex_q;

    // ------------------------------------------------------------------------
    // EX stage wires
    // ------------------------------------------------------------------------

    logic    [ 1:0] forward_a;
    logic    [ 1:0] forward_b;

    logic    [31:0] forwarded_rs1_data;
    logic    [31:0] forwarded_rs2_data;

    logic    [31:0] alu_operand_a;
    logic    [31:0] alu_operand_b;
    logic    [31:0] alu_result;
    logic    [31:0] ex_result;

    logic           muldiv_active;
    logic           muldiv_stall;
    logic           muldiv_result_ready;
    logic           muldiv_busy;
    logic           muldiv_done;
    logic    [31:0] muldiv_result;

    logic           branch_taken;
    logic           ex_redirect;
    logic    [31:0] jalr_target;
    logic    [31:0] ex_target;
    logic           control_target_misaligned;

    ex_mem_t        ex_mem_d;
    ex_mem_t        ex_mem_q;

    // ------------------------------------------------------------------------
    // MEM stage wires
    // ------------------------------------------------------------------------

    logic    [ 2:0] memory_funct3;
    logic    [31:0] memory_read_data;
    logic           data_access_fault;
    logic           ex_mem_fault;
    logic           data_request;
    logic           data_response_fire;
    logic           mem_response_consumed;

    logic                         dcache_req_ready;
    logic                         dcache_resp_valid;
    logic [31:0]                  dcache_resp_rdata;
    logic                         dcache_resp_hit;
    logic                         dcache_resp_miss;
    logic                         dcache_resp_fault;

    logic                         dmem_req_ready;
    logic                         dmem_req_valid;
    logic                         dmem_req_write;
    logic [31:0]                  dmem_req_addr;
    logic [CACHE_LINE_BITS-1:0]   dmem_req_wdata;
    logic                         dmem_resp_valid;
    logic [CACHE_LINE_BITS-1:0]   dmem_resp_rdata;
    logic                         dmem_resp_fault;
    logic                         dmem_resp_ready;

    mem_wb_t        mem_wb_d;
    mem_wb_t        mem_wb_q;

    // ------------------------------------------------------------------------
    // WB stage wires
    // ------------------------------------------------------------------------

    logic    [31:0] writeback_data;
    logic           commit_fault;
    logic           core_stop;

    // ------------------------------------------------------------------------
    // Hazard / control wires
    // ------------------------------------------------------------------------

    logic           load_stall_pc;
    logic           load_stall_if_id;
    logic           load_flush_id_ex;
    logic           load_use_stall;

    logic           pc_redirect;
    logic    [31:0] pc_target;
    logic           pc_stall;
    logic           stall_if_id;
    logic           flush_if_id;
    logic           flush_id_ex;
    logic           stall_id_ex;
    logic           stall_ex_mem;
    logic           flush_ex_mem;
    logic           mem_stall;

    // ------------------------------------------------------------------------
    // Debug outputs
    // ------------------------------------------------------------------------

    assign current_pc_o = pc;
    assign instruction_o = fetched_instruction;
    assign halted_o = core_stop;

    assign illegal_instruction_o = mem_wb_q.valid && mem_wb_q.illegal;
    assign instruction_fault_o = mem_wb_q.valid &&
                                 (mem_wb_q.instruction_fault ||
                                  mem_wb_q.control_target_misaligned);
    assign data_fault_o = mem_wb_q.valid && mem_wb_q.data_fault;

    // ------------------------------------------------------------------------
    // IF stage
    // ------------------------------------------------------------------------

    assign pc_plus_four = pc + 32'd4;

    // If pipeline_control redirects the PC, use that target.
    // Otherwise, keep fetching sequentially.
    assign next_pc = pc_redirect ? pc_target : pc_plus_four;

    pc u_pc (
        .clk    (clk_i),
        .rst    (rst_i),
        .en     (!pc_stall && !core_stop),
        .next_pc(next_pc),
        .pc     (pc)
    );

    icache #(
        .NUM_SETS  (ICACHE_NUM_SETS),
        .LINE_WORDS(CACHE_LINE_WORDS)
    ) u_icache (
        .clk            (clk_i),
        .rst            (rst_i),
        .cpu_req_valid  (!core_stop),
        .cpu_req_addr   (pc),
        .cpu_resp_valid (icache_resp_valid),
        .cpu_resp_rdata (fetched_instruction),
        .cpu_resp_fault (imem_access_fault),
        .cpu_stall      (icache_stall),
        .mem_req_ready  (imem_req_ready),
        .mem_req_valid  (imem_req_valid),
        .mem_req_addr   (imem_req_addr),
        .mem_resp_valid (imem_resp_valid),
        .mem_resp_rdata (imem_resp_rdata),
        .mem_resp_fault (imem_resp_fault),
        .mem_resp_ready (imem_resp_ready)
    );

    slow_line_memory #(
        .LINE_WORDS (CACHE_LINE_WORDS),
        .DEPTH_WORDS(IMEM_WORDS),
        .LATENCY    (IMEM_LATENCY),
        .HEX_FILE   (IMEM_HEX)
    ) u_imem (
        .clk       (clk_i),
        .rst       (rst_i),
        .req_valid (imem_req_valid),
        .req_ready (imem_req_ready),
        .req_write (1'b0),
        .req_addr  (imem_req_addr),
        .req_wdata ('0),
        .resp_valid(imem_resp_valid),
        .resp_ready(imem_resp_ready),
        .resp_rdata(imem_resp_rdata),
        .resp_fault(imem_resp_fault)
    );

    always_comb begin
        if_id_d = IF_ID_BUBBLE;

        // Only a completed hit or fault is allowed to enter Decode. A miss
        // leaves a bubble here while pipeline_control holds the old IF/ID.
        if_id_d.valid = icache_resp_valid && !core_stop;
        if_id_d.pc = pc;
        if_id_d.instruction = fetched_instruction;
        if_id_d.instruction_fault = imem_access_fault;
    end

    if_id_reg u_if_id_reg (
        .clk  (clk_i),
        .rst  (rst_i),
        .stall(stall_if_id),
        .flush(flush_if_id),
        .d    (if_id_d),
        .q    (if_id_q)
    );

    // ------------------------------------------------------------------------
    // ID stage
    // ------------------------------------------------------------------------

    assign rs1_addr = if_id_q.instruction[19:15];
    assign rs2_addr = if_id_q.instruction[24:20];
    assign rd_addr  = if_id_q.instruction[11:7];

    decoder u_decoder (
        .instruction  (if_id_q.instruction),
        .alu_op       (alu_op),
        .imm_sel      (imm_sel),
        .branch_op    (branch_op),
        .wb_sel       (wb_sel),
        .mem_size     (mem_size),
        .muldiv_op    (decode_muldiv_op),
        .reg_write    (reg_write),
        .alu_src_imm  (alu_src_imm),
        .alu_src_pc   (alu_src_pc),
        .mem_read     (mem_read),
        .mem_write    (mem_write),
        .load_unsigned(load_unsigned),
        .jump         (jump),
        .jalr         (jalr),
        .is_muldiv    (decode_is_muldiv),
        .halt         (halt),
        .illegal      (illegal)
    );

    imm_gen u_imm_gen (
        .instruction(if_id_q.instruction),
        .imm_sel    (imm_sel),
        .immediate  (immediate)
    );

    regfile u_regfile (
        .clk     (clk_i),
        .rs1_addr(rs1_addr),
        .rs2_addr(rs2_addr),
        .rs1_data(rs1_data),
        .rs2_data(rs2_data),
        .rd_addr (mem_wb_q.rd_addr),
        .rd_data (writeback_data),
        .we      (mem_wb_q.valid && mem_wb_q.reg_write && !commit_fault)
    );


    always_comb begin
        // Decode sees register-file reads, plus a small same-cycle WB bypass.
        // This covers when WB writes a register while ID reads it.
        decode_rs1_data = rs1_data;
        decode_rs2_data = rs2_data;

        if (mem_wb_q.valid && mem_wb_q.reg_write && !commit_fault && (mem_wb_q.rd_addr != 5'd0)) begin
            if (mem_wb_q.rd_addr == rs1_addr) decode_rs1_data = writeback_data;
            if (mem_wb_q.rd_addr == rs2_addr) decode_rs2_data = writeback_data;
        end
    end

    always_comb begin
        id_ex_d = ID_EX_BUBBLE;

        if (if_id_q.valid) begin
            id_ex_d.valid = 1'b1;

            id_ex_d.pc = if_id_q.pc;
            id_ex_d.pc_plus_four = if_id_q.pc + 32'd4;
            // Compute the branch/JAL target before EX. The branch comparison
            // still happens in EX, but its result no longer feeds a 32-bit
            // target adder on the path to the PC register.
            id_ex_d.pc_relative_target = if_id_q.pc + immediate;

            id_ex_d.rs1_addr = rs1_addr;
            id_ex_d.rs2_addr = rs2_addr;
            id_ex_d.rd_addr = rd_addr;

            id_ex_d.rs1_data = decode_rs1_data;
            id_ex_d.rs2_data = decode_rs2_data;
            id_ex_d.immediate = immediate;

            id_ex_d.alu_op = alu_op_t'(alu_op);
            id_ex_d.muldiv_op = decode_muldiv_op;
            id_ex_d.branch_op = branch_op_t'(branch_op);
            id_ex_d.wb_sel = wb_sel_t'(wb_sel);
            id_ex_d.mem_size = mem_size_t'(mem_size);

            id_ex_d.alu_src_imm = alu_src_imm;
            id_ex_d.alu_src_pc = alu_src_pc;
            id_ex_d.is_muldiv = decode_is_muldiv;

            id_ex_d.reg_write = reg_write;
            id_ex_d.mem_read = mem_read;
            id_ex_d.mem_write = mem_write;
            id_ex_d.load_unsigned = load_unsigned;

            id_ex_d.jump = jump;
            id_ex_d.jalr = jalr;
            id_ex_d.halt = halt;
            id_ex_d.illegal = illegal;
            id_ex_d.instruction_fault = if_id_q.instruction_fault;
        end
    end

    id_ex_reg u_id_ex_reg (
        .clk   (clk_i),
        .rst   (rst_i),
        .en    (!stall_id_ex),
        .flush (flush_id_ex),
        .data  (id_ex_d),
        .data_o(id_ex_q)
    );

    // ------------------------------------------------------------------------
    // Hazard detection
    // ------------------------------------------------------------------------

    load_use_hazard_unit u_load_use_hazard_unit (
        .if_id_valid   (if_id_q.valid),
        .if_id_rs1_addr(rs1_addr),
        .if_id_rs2_addr(rs2_addr),
        .id_ex_data    (id_ex_q),
        .stall_pc      (load_stall_pc),
        .stall_if_id   (load_stall_if_id),
        .flush_id_ex   (load_flush_id_ex)
    );

    assign load_use_stall = load_stall_pc;

    // ------------------------------------------------------------------------
    // EX stage
    // ------------------------------------------------------------------------

    forwarding_unit u_forwarding_unit (
        .rs1_addr   (id_ex_q.rs1_addr),
        .rs2_addr   (id_ex_q.rs2_addr),
        .ex_mem_data(ex_mem_q),
        .mem_wb_data(mem_wb_q),
        .forward_a  (forward_a),
        .forward_b  (forward_b)
    );

    always_comb begin
        forwarded_rs1_data = id_ex_q.rs1_data;
        forwarded_rs2_data = id_ex_q.rs2_data;

        case (forward_a)
            2'b01:   forwarded_rs1_data = writeback_data;
            2'b10:   forwarded_rs1_data = ex_mem_q.alu_result;
            default: forwarded_rs1_data = id_ex_q.rs1_data;
        endcase

        case (forward_b)
            2'b01:   forwarded_rs2_data = writeback_data;
            2'b10:   forwarded_rs2_data = ex_mem_q.alu_result;
            default: forwarded_rs2_data = id_ex_q.rs2_data;
        endcase
    end

    assign alu_operand_a = id_ex_q.alu_src_pc ? id_ex_q.pc : forwarded_rs1_data;
    assign alu_operand_b = id_ex_q.alu_src_imm ? id_ex_q.immediate : forwarded_rs2_data;

    alu u_alu (
        .op_a  (alu_operand_a),
        .op_b  (alu_operand_b),
        .alu_op(id_ex_q.alu_op),
        .result(alu_result),
        .zero  ()
    );

    // Multi-cycle MUL/DIV shares the forwarded EX operands with the ALU. A
    // completed result only needs to wait when the older MEM instruction is
    // back-pressured. The other source of stall_id_ex is muldiv_stall itself,
    // which cannot coincide with a completed result.
    assign muldiv_active = id_ex_q.valid && id_ex_q.is_muldiv;
    assign muldiv_result_ready = !mem_stall;

    muldiv_unit u_muldiv_unit (
        .clk     (clk_i),
        .rst     (rst_i),
        .in_valid(muldiv_active),
        .funct3  (id_ex_q.muldiv_op),
        .rs1_data(forwarded_rs1_data),
        .rs2_data(forwarded_rs2_data),
        .result_ready(muldiv_result_ready),
        .result  (muldiv_result),
        .busy    (muldiv_busy),
        .done    (muldiv_done)
    );

    // Stall the pipeline while a muldiv op is in EX and has not yet produced a
    // result. On the done cycle the stall drops and the result advances.
    assign muldiv_stall = muldiv_active && !muldiv_done;

    // EX result feeding EX/MEM: the muldiv result replaces the ALU result for
    // M-extension ops, writing back through the normal WB_ALU path.
    assign ex_result = id_ex_q.is_muldiv ? muldiv_result : alu_result;

    branch_unit u_branch_unit (
        .rs1_data    (forwarded_rs1_data),
        .rs2_data    (forwarded_rs2_data),
        .branch_op   (id_ex_q.branch_op),
        .branch_taken(branch_taken)
    );

    assign ex_redirect = id_ex_q.valid && (id_ex_q.jump || branch_taken);

    // JALR gets a dedicated target adder. Reusing the general ALU placed its
    // operand and operation muxes in the MEM/WB-forwarding-to-PC timing path.
    assign jalr_target = (forwarded_rs1_data + id_ex_q.immediate) &
                         32'hffff_fffe;
    assign ex_target = id_ex_q.jalr ? jalr_target :
                       id_ex_q.pc_relative_target;

    assign control_target_misaligned = ex_redirect && (ex_target[1:0] != 2'b00);

    always_comb begin
        ex_mem_d = EX_MEM_BUBBLE;

        if (id_ex_q.valid) begin
            ex_mem_d.valid = 1'b1;

            ex_mem_d.pc = id_ex_q.pc;
            ex_mem_d.pc_plus_four = id_ex_q.pc_plus_four;
            ex_mem_d.alu_result = ex_result;
            ex_mem_d.store_data = forwarded_rs2_data;
            ex_mem_d.rd_addr = id_ex_q.rd_addr;

            ex_mem_d.wb_sel = id_ex_q.wb_sel;
            ex_mem_d.mem_size = id_ex_q.mem_size;

            ex_mem_d.reg_write = id_ex_q.reg_write;
            ex_mem_d.mem_read = id_ex_q.mem_read;
            ex_mem_d.mem_write = id_ex_q.mem_write;
            ex_mem_d.load_unsigned = id_ex_q.load_unsigned;

            ex_mem_d.halt = id_ex_q.halt;
            ex_mem_d.illegal = id_ex_q.illegal;
            ex_mem_d.instruction_fault = id_ex_q.instruction_fault;
            ex_mem_d.control_target_misaligned = control_target_misaligned;
        end
    end

    ex_mem_reg u_ex_mem_reg (
        .clk   (clk_i),
        .rst   (rst_i),
        .en    (!stall_ex_mem),
        .flush (flush_ex_mem),
        .data  (ex_mem_d),
        .data_o(ex_mem_q)
    );

    // ------------------------------------------------------------------------
    // Pipeline control
    // ------------------------------------------------------------------------

    pipeline_control u_pipeline_control (
        .ex_redirect   (ex_redirect),
        .ex_target     (ex_target),
        .load_use_stall(load_use_stall),
        .muldiv_stall  (muldiv_stall),
        .mem_stall     (mem_stall),
        .if_stall      (icache_stall),
        .trap_req      (1'b0),
        .trap_target   (32'b0),
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

    // ------------------------------------------------------------------------
    // MEM stage
    // ------------------------------------------------------------------------

    assign memory_funct3 = {ex_mem_q.load_unsigned, ex_mem_q.mem_size};

    assign ex_mem_fault = ex_mem_q.illegal ||
                          ex_mem_q.instruction_fault ||
                          ex_mem_q.control_target_misaligned;

    assign data_request = ex_mem_q.valid &&
                          (ex_mem_q.mem_read || ex_mem_q.mem_write) &&
                          !ex_mem_fault &&
                          !core_stop;

    // Keep the memory instruction in EX/MEM through the response edge. The
    // following cycle, its result is in MEM/WB for normal forwarding and the
    // held dependent instruction can safely advance from EX.
    assign data_response_fire = dcache_resp_valid && !mem_response_consumed;
    assign mem_stall = data_request && !mem_response_consumed;

    always_ff @(posedge clk_i) begin
        if (rst_i)
            mem_response_consumed <= 1'b0;
        else if (data_response_fire)
            mem_response_consumed <= 1'b1;
        else if (!stall_ex_mem)
            mem_response_consumed <= 1'b0;
    end

    dcache #(
        .NUM_SETS  (DCACHE_NUM_SETS),
        .NUM_WAYS  (DCACHE_NUM_WAYS),
        .LINE_WORDS(CACHE_LINE_WORDS)
    ) u_dcache (
        .clk            (clk_i),
        .rst            (rst_i),
        .cpu_req_valid  (data_request && !mem_response_consumed),
        .cpu_req_write  (ex_mem_q.mem_write),
        .cpu_req_addr   (ex_mem_q.alu_result),
        .cpu_req_wdata  (ex_mem_q.store_data),
        .cpu_req_funct3 (memory_funct3),
        .cpu_req_ready  (dcache_req_ready),
        .cpu_resp_ready (!mem_response_consumed),
        .cpu_resp_valid (dcache_resp_valid),
        .cpu_resp_rdata (dcache_resp_rdata),
        .cpu_resp_hit   (dcache_resp_hit),
        .cpu_resp_miss  (dcache_resp_miss),
        .cpu_resp_fault (dcache_resp_fault),
        .mem_req_ready  (dmem_req_ready),
        .mem_req_valid  (dmem_req_valid),
        .mem_req_write  (dmem_req_write),
        .mem_req_addr   (dmem_req_addr),
        .mem_req_wdata  (dmem_req_wdata),
        .mem_resp_valid (dmem_resp_valid),
        .mem_resp_rdata (dmem_resp_rdata),
        .mem_resp_fault (dmem_resp_fault),
        .mem_resp_ready (dmem_resp_ready)
    );

    slow_line_memory #(
        .LINE_WORDS (CACHE_LINE_WORDS),
        .DEPTH_WORDS(DMEM_WORDS),
        .LATENCY    (DMEM_LATENCY),
        .HEX_FILE   (DMEM_HEX)
    ) u_dmem (
        .clk       (clk_i),
        .rst       (rst_i),
        .req_valid (dmem_req_valid),
        .req_ready (dmem_req_ready),
        .req_write (dmem_req_write),
        .req_addr  (dmem_req_addr),
        .req_wdata (dmem_req_wdata),
        .resp_valid(dmem_resp_valid),
        .resp_ready(dmem_resp_ready),
        .resp_rdata(dmem_resp_rdata),
        .resp_fault(dmem_resp_fault)
    );

    assign memory_read_data = dcache_resp_rdata;
    assign data_access_fault = dcache_resp_valid && dcache_resp_fault;

    always_comb begin
        mem_wb_d = MEM_WB_BUBBLE;

        if (ex_mem_q.valid &&
            (!(ex_mem_q.mem_read || ex_mem_q.mem_write) ||
             ex_mem_fault ||
             data_response_fire)) begin
            mem_wb_d.valid = 1'b1;

            mem_wb_d.pc = ex_mem_q.pc;
            mem_wb_d.pc_plus_four = ex_mem_q.pc_plus_four;
            mem_wb_d.alu_result = ex_mem_q.alu_result;
            mem_wb_d.memory_read_data = memory_read_data;
            mem_wb_d.rd_addr = ex_mem_q.rd_addr;

            mem_wb_d.wb_sel = ex_mem_q.wb_sel;
            mem_wb_d.reg_write = ex_mem_q.reg_write;

            mem_wb_d.halt = ex_mem_q.halt;
            mem_wb_d.illegal = ex_mem_q.illegal;
            mem_wb_d.instruction_fault = ex_mem_q.instruction_fault;
            mem_wb_d.data_fault = data_access_fault;
            mem_wb_d.control_target_misaligned = ex_mem_q.control_target_misaligned;
        end
    end

    mem_wb_reg u_mem_wb_reg (
        .clk  (clk_i),
        .rst  (rst_i),
        .flush(1'b0),
        .d    (mem_wb_d),
        .q    (mem_wb_q)
    );

    // ------------------------------------------------------------------------
    // WB stage
    // ------------------------------------------------------------------------

    always_comb begin
        case (mem_wb_q.wb_sel)
            WB_ALU:  writeback_data = mem_wb_q.alu_result;
            WB_MEM:  writeback_data = mem_wb_q.memory_read_data;
            WB_PC4:  writeback_data = mem_wb_q.pc_plus_four;
            default: writeback_data = '0;
        endcase
    end

    assign commit_fault = mem_wb_q.illegal ||
                          mem_wb_q.instruction_fault ||
                          mem_wb_q.data_fault ||
                          mem_wb_q.control_target_misaligned;

    assign core_stop = mem_wb_q.valid && (mem_wb_q.halt || commit_fault);

endmodule

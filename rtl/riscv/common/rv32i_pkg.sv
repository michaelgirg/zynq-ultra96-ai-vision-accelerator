package rv32i_pkg;

    localparam int XLEN = 32;
    localparam int NUM_REGISTERS = 32;

    // ALU control values shared by the decoder and ALU.
    typedef enum logic [3:0] {
        ALU_ADD    = 4'd0,
        ALU_SUB    = 4'd1,
        ALU_SLL    = 4'd2,
        ALU_SRL    = 4'd3,
        ALU_SRA    = 4'd4,
        ALU_AND    = 4'd5,
        ALU_OR     = 4'd6,
        ALU_XOR    = 4'd7,
        ALU_SLT    = 4'd8,
        ALU_SLTU   = 4'd9,
        ALU_COPY_B = 4'd10
    } alu_op_t;

    typedef enum logic [2:0] {
        IMM_I = 3'd0,
        IMM_S = 3'd1,
        IMM_B = 3'd2,
        IMM_U = 3'd3,
        IMM_J = 3'd4
    } imm_sel_t;

    typedef enum logic [2:0] {
        BR_NONE = 3'd0,
        BR_EQ   = 3'd1,
        BR_NE   = 3'd2,
        BR_LT   = 3'd3,
        BR_GE   = 3'd4,
        BR_LTU  = 3'd5,
        BR_GEU  = 3'd6
    } branch_op_t;

    typedef enum logic [1:0] {
        WB_ALU = 2'd0,
        WB_MEM = 2'd1,
        WB_PC4 = 2'd2
    } wb_sel_t;

    typedef enum logic [1:0] {
        MEM_BYTE = 2'd0,
        MEM_HALF = 2'd1,
        MEM_WORD = 2'd2
    } mem_size_t;

    // RV32M operation encoding. These values intentionally match funct3 so
    // the decoder can carry the instruction's operation directly into the
    // multiply/divide execute unit.
    typedef enum logic [2:0] {
        MULDIV_MUL    = 3'b000,
        MULDIV_MULH   = 3'b001,
        MULDIV_MULHSU = 3'b010,
        MULDIV_MULHU  = 3'b011,
        MULDIV_DIV    = 3'b100,
        MULDIV_DIVU   = 3'b101,
        MULDIV_REM    = 3'b110,
        MULDIV_REMU   = 3'b111
    } muldiv_op_t;

    // RV32I funct3 encodings used by the data memory.
    localparam logic [2:0] LOAD_BYTE = 3'b000;
    localparam logic [2:0] LOAD_HALF = 3'b001;
    localparam logic [2:0] LOAD_WORD = 3'b010;
    localparam logic [2:0] LOAD_BYTE_U = 3'b100;
    localparam logic [2:0] LOAD_HALF_U = 3'b101;

    localparam logic [2:0] STORE_BYTE = 3'b000;
    localparam logic [2:0] STORE_HALF = 3'b001;
    localparam logic [2:0] STORE_WORD = 3'b010;

    // RV32I major opcodes, ordered as shown in the ISA table.
    localparam logic [6:0] OP_LUI = 7'b0110111;
    localparam logic [6:0] OP_AUIPC = 7'b0010111;
    localparam logic [6:0] OP_JAL = 7'b1101111;
    localparam logic [6:0] OP_JALR = 7'b1100111;
    localparam logic [6:0] OP_BRANCH = 7'b1100011;
    localparam logic [6:0] OP_LOAD = 7'b0000011;
    localparam logic [6:0] OP_STORE = 7'b0100011;
    localparam logic [6:0] OP_IMM = 7'b0010011;
    localparam logic [6:0] OP_REG = 7'b0110011;
    localparam logic [6:0] OP_FENCE = 7'b0001111;
    localparam logic [6:0] OP_SYSTEM = 7'b1110011;

    localparam logic [31:0] INSTRUCTION_NOP = 32'h0000_0013;
    localparam logic [31:0] INSTRUCTION_ECALL = 32'h0000_0073;
    localparam logic [31:0] INSTRUCTION_EBREAK = 32'h0010_0073;
    localparam logic [31:0] INSTRUCTION_FENCE_I = 32'h0000_100f;

    // Pipeline-register payloads
    //
    // These packed structs define exactly what information crosses each stage
    // boundary. Keeping them in the shared package prevents the top level and
    // the four pipeline-register modules from disagreeing about field names or
    // widths.

    // Information produced by Instruction Fetch and consumed by Decode.
    typedef struct packed {
        // valid = 1 means this entry contains a real instruction.
        // valid = 0 means this entry is an empty pipeline bubble.
        logic        valid;
        logic [31:0] pc;
        logic [31:0] instruction;
        logic        instruction_fault;
    } if_id_t;

    // Decoded instruction information consumed by the Execute stage.
    typedef struct packed {
        logic        valid;

        // Address information used by branches, jumps, and link writeback.
        logic [31:0] pc;
        logic [31:0] pc_plus_four;
        logic [31:0] pc_relative_target;

        // Register addresses are retained for hazard detection and forwarding.
        logic [4:0]  rs1_addr;
        logic [4:0]  rs2_addr;
        logic [4:0]  rd_addr;

        // Operand values read during Decode.
        logic [31:0] rs1_data;
        logic [31:0] rs2_data;
        logic [31:0] immediate;

        // Decoded operation selections.
        alu_op_t     alu_op;
        muldiv_op_t  muldiv_op;
        branch_op_t  branch_op;
        wb_sel_t     wb_sel;
        mem_size_t   mem_size;

        // Datapath controls.
        logic        alu_src_imm;
        logic        alu_src_pc;
        logic        is_muldiv;

        // Register and memory side-effect controls.
        logic        reg_write;
        logic        mem_read;
        logic        mem_write;
        logic        load_unsigned;

        // Control-flow and exceptional conditions.
        logic        jump;
        logic        jalr;
        logic        halt;
        logic        illegal;
        logic        instruction_fault;
    } id_ex_t;

    // Execute results and controls consumed by the Memory stage.
    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] pc_plus_four;
        logic [31:0] alu_result;
        logic [31:0] store_data;
        logic [4:0]  rd_addr;

        wb_sel_t     wb_sel;
        mem_size_t   mem_size;

        logic        reg_write;
        logic        mem_read;
        logic        mem_write;
        logic        load_unsigned;

        logic        halt;
        logic        illegal;
        logic        instruction_fault;
        logic        control_target_misaligned;
    } ex_mem_t;

    // Final results and controls consumed by the Writeback stage.
    typedef struct packed {
        logic        valid;
        logic [31:0] pc;
        logic [31:0] pc_plus_four;
        logic [31:0] alu_result;
        logic [31:0] memory_read_data;
        logic [4:0]  rd_addr;

        wb_sel_t     wb_sel;
        logic        reg_write;

        logic        halt;
        logic        illegal;
        logic        instruction_fault;
        logic        data_fault;
        logic        control_target_misaligned;
    } mem_wb_t;

    // A bubble is not literal "nothing." Hardware bits must still contain
    // values, so every field is cleared to zero. Most importantly, valid is
    // zero, which tells later stages not to treat the entry as an instruction
    // or allow it to change registers or memory.
    localparam if_id_t  IF_ID_BUBBLE  = '0;
    localparam id_ex_t  ID_EX_BUBBLE  = '0;
    localparam ex_mem_t EX_MEM_BUBBLE = '0;
    localparam mem_wb_t MEM_WB_BUBBLE = '0;

endpackage

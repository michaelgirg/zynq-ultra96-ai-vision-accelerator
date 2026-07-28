// Decoder
//
// This module decodes a 32-bit RV32I instruction and generates the control
// signals needed by the datapath. It extracts opcode, funct3, and funct7 to
// determine the instruction type, ALU operation, immediate format, branch
// operation, memory access size, writeback source, and register/memory control
// enables.
//
// The decoder DOES NOT execute instructions directly. It only tells the ALU,
// immediate generator, branch unit, memory system, register file, writeback mux,
// and PC logic how to behave for the current instruction.
//
// Unsupported or invalid instruction encodings assert illegal, and illegal
// instructions are prevented from writing registers, accessing memory, jumping,
// branching, or halting the core.

module decoder (
    input logic [31:0] instruction,

    output logic [3:0] alu_op,     // Operation performed by the ALU
    output logic [2:0] imm_sel,    // Immediate format built by imm_gen
    output logic [2:0] branch_op,  // Comparison performed by branch_unit
    output logic [1:0] wb_sel,     // Value selected for register writeback
    output logic [1:0] mem_size,   // Byte, halfword, or word memory access
    output rv32i_pkg::muldiv_op_t muldiv_op,

    output logic reg_write,
    output logic alu_src_imm,    // Selects the immediate instead of rs2
    output logic alu_src_pc,     // Selects the PC instead of rs1
    output logic mem_read,
    output logic mem_write,
    output logic load_unsigned,
    output logic jump,
    output logic jalr,
    output logic is_muldiv,
    output logic halt,
    output logic illegal
);
    import rv32i_pkg::*;

    logic [6:0] opcode;
    logic [2:0] funct3;
    logic [6:0] funct7;

    assign opcode = instruction[6:0];
    assign funct3 = instruction[14:12];
    assign funct7 = instruction[31:25];

    always_comb begin
        // Safe defaults prevent latch inference.
        alu_op        = ALU_ADD;
        imm_sel       = IMM_I;
        branch_op     = BR_NONE;
        wb_sel        = WB_ALU;
        mem_size      = MEM_WORD;
        muldiv_op     = MULDIV_MUL;

        reg_write     = 1'b0;
        alu_src_imm   = 1'b0;
        alu_src_pc    = 1'b0;
        mem_read      = 1'b0;
        mem_write     = 1'b0;
        load_unsigned = 1'b0;
        jump          = 1'b0;
        jalr          = 1'b0;
        is_muldiv     = 1'b0;
        halt          = 1'b0;
        illegal       = 1'b0;

        case (opcode)
            OP_LUI: begin
                // rd = U-immediate
                reg_write   = 1'b1;
                alu_src_imm = 1'b1;
                imm_sel     = IMM_U;
                alu_op      = ALU_COPY_B;
            end

            OP_AUIPC: begin
                // rd = PC + U-immediate
                reg_write   = 1'b1;
                alu_src_pc  = 1'b1;
                alu_src_imm = 1'b1;
                imm_sel     = IMM_U;
                alu_op      = ALU_ADD;
            end

            OP_JAL: begin
                // rd = PC + 4
                // next PC = PC + J-immediate
                reg_write = 1'b1;
                jump      = 1'b1;
                imm_sel   = IMM_J;
                wb_sel    = WB_PC4;
            end

            OP_JALR: begin
                // rd = PC + 4
                // next PC = (rs1 + I-immediate) & ~1

                reg_write   = 1'b1;
                alu_src_imm = 1'b1;
                jump        = 1'b1;
                jalr        = 1'b1;
                imm_sel     = IMM_I;
                wb_sel      = WB_PC4;

                // JALR requires funct3 = 000
                if (funct3 != 3'b000) begin
                    illegal = 1'b1;
                end
            end

            OP_BRANCH: begin
                imm_sel = IMM_B;

                case (funct3)
                    3'b000:  branch_op = BR_EQ;
                    3'b001:  branch_op = BR_NE;
                    3'b100:  branch_op = BR_LT;
                    3'b101:  branch_op = BR_GE;
                    3'b110:  branch_op = BR_LTU;
                    3'b111:  branch_op = BR_GEU;
                    default: illegal = 1'b1;
                endcase
            end

            OP_LOAD: begin
                reg_write   = 1'b1;
                alu_src_imm = 1'b1;
                mem_read    = 1'b1;
                imm_sel     = IMM_I;
                alu_op      = ALU_ADD;
                wb_sel      = WB_MEM;

                case (funct3)
                    3'b000: mem_size = MEM_BYTE;  // LB
                    3'b001: mem_size = MEM_HALF;  // LH
                    3'b010: mem_size = MEM_WORD;  // LW

                    3'b100: begin  // LBU
                        mem_size      = MEM_BYTE;
                        load_unsigned = 1'b1;
                    end

                    3'b101: begin  // LHU
                        mem_size      = MEM_HALF;
                        load_unsigned = 1'b1;
                    end

                    default: illegal = 1'b1;
                endcase
            end

            OP_STORE: begin
                alu_src_imm = 1'b1;
                mem_write   = 1'b1;
                imm_sel     = IMM_S;
                alu_op      = ALU_ADD;

                case (funct3)
                    3'b000:  mem_size = MEM_BYTE;  // SB
                    3'b001:  mem_size = MEM_HALF;  // SH
                    3'b010:  mem_size = MEM_WORD;  // SW
                    default: illegal = 1'b1;
                endcase
            end

            OP_IMM: begin
                reg_write   = 1'b1;
                alu_src_imm = 1'b1;
                imm_sel     = IMM_I;

                case (funct3)
                    3'b000: alu_op = ALU_ADD;  // ADDI
                    3'b010: alu_op = ALU_SLT;  // SLTI
                    3'b011: alu_op = ALU_SLTU;  // SLTIU
                    3'b100: alu_op = ALU_XOR;  // XORI
                    3'b110: alu_op = ALU_OR;  // ORI
                    3'b111: alu_op = ALU_AND;  // ANDI

                    3'b001: begin  // SLLI
                        alu_op = ALU_SLL;

                        if (funct7 != 7'b0000000) begin
                            illegal = 1'b1;
                        end
                    end

                    3'b101: begin
                        if (funct7 == 7'b0000000) begin
                            alu_op = ALU_SRL;  // SRLI
                        end else if (funct7 == 7'b0100000) begin
                            alu_op = ALU_SRA;  // SRAI
                        end else begin
                            illegal = 1'b1;
                        end
                    end

                    default: illegal = 1'b1;
                endcase
            end

            OP_REG: begin
                reg_write = 1'b1;

                if (funct7 == 7'b0000001) begin
                    // All eight funct3 values are defined by RV32M. The
                    // execute unit uses muldiv_op to select multiply, divide,
                    // or remainder behavior.
                    is_muldiv = 1'b1;
                    muldiv_op = muldiv_op_t'(funct3);
                end else begin
                    case (funct3)
                    3'b000: begin
                        if (funct7 == 7'b0000000) begin
                            alu_op = ALU_ADD;
                        end else if (funct7 == 7'b0100000) begin
                            alu_op = ALU_SUB;
                        end else begin
                            illegal = 1'b1;
                        end
                    end

                    3'b001: begin
                        alu_op = ALU_SLL;
                        if (funct7 != 7'b0000000) begin
                            illegal = 1'b1;
                        end
                    end

                    3'b010: begin
                        alu_op = ALU_SLT;
                        if (funct7 != 7'b0000000) begin
                            illegal = 1'b1;
                        end
                    end

                    3'b011: begin
                        alu_op = ALU_SLTU;
                        if (funct7 != 7'b0000000) begin
                            illegal = 1'b1;
                        end
                    end

                    3'b100: begin
                        alu_op = ALU_XOR;
                        if (funct7 != 7'b0000000) begin
                            illegal = 1'b1;
                        end
                    end

                    3'b101: begin
                        if (funct7 == 7'b0000000) begin
                            alu_op = ALU_SRL;
                        end else if (funct7 == 7'b0100000) begin
                            alu_op = ALU_SRA;
                        end else begin
                            illegal = 1'b1;
                        end
                    end

                    3'b110: begin
                        alu_op = ALU_OR;
                        if (funct7 != 7'b0000000) begin
                            illegal = 1'b1;
                        end
                    end

                    3'b111: begin
                        alu_op = ALU_AND;
                        if (funct7 != 7'b0000000) begin
                            illegal = 1'b1;
                        end
                    end

                    default: illegal = 1'b1;
                endcase
                end
            end

            OP_FENCE: begin
                // FENCE and FENCE.I act as NOPs in this initial core.
                case (funct3)
                    // Reserved fields are ignored for forward compatibility.
                    3'b000: begin end
                    3'b001: begin end
                    default: illegal = 1'b1;
                endcase
            end

            OP_SYSTEM: begin
                if ((instruction == 32'h0000_0073) || (instruction == 32'h0010_0073)) begin
                    halt = 1'b1;  // ECALL or EBREAK
                end else begin
                    illegal = 1'b1;
                end
            end

            default: begin
                illegal = 1'b1;
            end
        endcase

        // Future design notes:
        // - FENCE can remain a NOP in this single-cycle core because memory
        //   operations already complete in program order. A pipelined or
        //   out-of-order implementation must enforce the requested ordering.
        // - FENCE.I matters once instruction data can be modified or cached.
        // - ECALL and EBREAK halt this simple simulation environment. Other
        //   SYSTEM instructions remain illegal until CSR and trap support
        //   are implemented.

        // Prevent illegal instructions from changing architectural state.
        if (illegal) begin
            reg_write = 1'b0;
            mem_read  = 1'b0;
            mem_write = 1'b0;
            jump      = 1'b0;
            is_muldiv = 1'b0;
            halt      = 1'b0;
            branch_op = BR_NONE;
        end
    end

endmodule

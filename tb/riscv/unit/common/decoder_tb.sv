`timescale 1 ns / 100 ps

module decoder_tb #(
    parameter int NUM_RANDOM_TESTS = 2000
);
    import rv32i_pkg::*;

    logic [31:0] instruction;
    logic [3:0]  alu_op;
    logic [2:0]  imm_sel;
    logic [2:0]  branch_op;
    logic [1:0]  wb_sel;
    logic [1:0]  mem_size;
    muldiv_op_t  muldiv_op;
    logic        reg_write;
    logic        alu_src_imm;
    logic        alu_src_pc;
    logic        mem_read;
    logic        mem_write;
    logic        load_unsigned;
    logic        jump;
    logic        jalr;
    logic        is_muldiv;
    logic        halt;
    logic        illegal;

    int errors = 0;
    int legal_tests = 0;
    int illegal_tests = 0;
    int opcode_hits [0:127];

    decoder DUT (.*);

    function automatic logic [31:0] encode_u(
        input logic [6:0] opcode
    );
        return {20'h12345, 5'd3, opcode};
    endfunction

    function automatic logic [31:0] encode_i(
        input logic [11:0] imm,
        input logic [2:0]  funct3,
        input logic [6:0]  opcode
    );
        return {imm, 5'd1, funct3, 5'd3, opcode};
    endfunction

    function automatic logic [31:0] encode_s(input logic [2:0] funct3);
        logic [11:0] imm = 12'h008;
        return {imm[11:5], 5'd2, 5'd1, funct3, imm[4:0], 7'b0100011};
    endfunction

    function automatic logic [31:0] encode_b(input logic [2:0] funct3);
        logic [12:0] imm = 13'h008;
        return {
            imm[12],
            imm[10:5],
            5'd2,
            5'd1,
            funct3,
            imm[4:1],
            imm[11],
            7'b1100011
        };
    endfunction

    function automatic logic [31:0] encode_r(
        input logic [6:0] funct7,
        input logic [2:0] funct3
    );
        return {funct7, 5'd2, 5'd1, funct3, 5'd3, 7'b0110011};
    endfunction

    function automatic logic known_opcode(input logic [6:0] test_opcode);
        case (test_opcode)
            OP_LUI,
            OP_AUIPC,
            OP_JAL,
            OP_JALR,
            OP_BRANCH,
            OP_LOAD,
            OP_STORE,
            OP_IMM,
            OP_REG,
            OP_FENCE,
            OP_SYSTEM: return 1'b1;
            default: return 1'b0;
        endcase
    endfunction

    task automatic check_controls(
        input string       test_name,
        input logic [31:0] test_instruction,
        input logic [3:0]  expected_alu_op,
        input logic [2:0]  expected_imm_sel,
        input logic [2:0]  expected_branch_op,
        input logic [1:0]  expected_wb_sel,
        input logic [1:0]  expected_mem_size,
        input logic        expected_reg_write,
        input logic        expected_alu_src_imm,
        input logic        expected_alu_src_pc,
        input logic        expected_mem_read,
        input logic        expected_mem_write,
        input logic        expected_load_unsigned,
        input logic        expected_jump,
        input logic        expected_jalr,
        input logic        expected_halt,
        input logic        expected_illegal
    );
        logic [23:0] expected;
        logic [23:0] actual;

        instruction = test_instruction;
        #1;
        opcode_hits[test_instruction[6:0]]++;
        if (expected_illegal) illegal_tests++;
        else legal_tests++;

        expected = {
            expected_alu_op,
            expected_imm_sel,
            expected_branch_op,
            expected_wb_sel,
            expected_mem_size,
            expected_reg_write,
            expected_alu_src_imm,
            expected_alu_src_pc,
            expected_mem_read,
            expected_mem_write,
            expected_load_unsigned,
            expected_jump,
            expected_jalr,
            expected_halt,
            expected_illegal
        };

        actual = {
            alu_op,
            imm_sel,
            branch_op,
            wb_sel,
            mem_size,
            reg_write,
            alu_src_imm,
            alu_src_pc,
            mem_read,
            mem_write,
            load_unsigned,
            jump,
            jalr,
            halt,
            illegal
        };

        if (actual !== expected) begin
            $error(
                "%s: instruction=%h expected controls=%b actual controls=%b",
                test_name,
                test_instruction,
                expected,
                actual
            );
            errors++;
        end

        if (is_muldiv !== 1'b0) begin
            $error("%s: non-RV32M instruction asserted is_muldiv", test_name);
            errors++;
        end
    endtask

    task automatic check_alu_imm(
        input string       test_name,
        input logic [31:0] test_instruction,
        input logic [3:0]  expected_alu_op
    );
        check_controls(
            test_name, test_instruction,
            expected_alu_op, IMM_I, BR_NONE, WB_ALU, MEM_WORD,
            1'b1, 1'b1, 1'b0, 1'b0, 1'b0,
            1'b0, 1'b0, 1'b0, 1'b0, 1'b0
        );
    endtask

    task automatic check_alu_reg(
        input string       test_name,
        input logic [31:0] test_instruction,
        input logic [3:0]  expected_alu_op
    );
        check_controls(
            test_name, test_instruction,
            expected_alu_op, IMM_I, BR_NONE, WB_ALU, MEM_WORD,
            1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
            1'b0, 1'b0, 1'b0, 1'b0, 1'b0
        );
    endtask

    task automatic check_muldiv(
        input string      test_name,
        input logic [2:0] test_funct3,
        input muldiv_op_t expected_muldiv_op
    );
        instruction = encode_r(7'b0000001, test_funct3);
        #1;
        opcode_hits[OP_REG]++;
        legal_tests++;

        if ((illegal !== 1'b0) ||
            (reg_write !== 1'b1) ||
            (is_muldiv !== 1'b1) ||
            (muldiv_op !== expected_muldiv_op) ||
            (wb_sel !== WB_ALU) ||
            (alu_src_imm !== 1'b0) ||
            (alu_src_pc !== 1'b0) ||
            (mem_read !== 1'b0) ||
            (mem_write !== 1'b0) ||
            (jump !== 1'b0) ||
            (jalr !== 1'b0) ||
            (halt !== 1'b0)) begin
            $error(
                "%s: funct3=%03b did not produce the expected RV32M controls",
                test_name,
                test_funct3
            );
            errors++;
        end
    endtask

    task automatic check_illegal(
        input string       test_name,
        input logic [31:0] test_instruction
    );
        instruction = test_instruction;
        #1;
        opcode_hits[test_instruction[6:0]]++;
        illegal_tests++;

        if (illegal !== 1'b1) begin
            $error("%s: illegal was not asserted", test_name);
            errors++;
        end

        if ((reg_write !== 1'b0) ||
            (mem_read  !== 1'b0) ||
            (mem_write !== 1'b0) ||
            (jump      !== 1'b0) ||
            (is_muldiv !== 1'b0) ||
            (halt      !== 1'b0) ||
            (branch_op !== BR_NONE)) begin
            $error("%s: illegal instruction retained an architectural side effect", test_name);
            errors++;
        end
    endtask

    initial begin
        // Upper-immediate and jump instructions
        check_controls(
            "LUI", encode_u(7'b0110111),
            ALU_COPY_B, IMM_U, BR_NONE, WB_ALU, MEM_WORD,
            1'b1, 1'b1, 1'b0, 1'b0, 1'b0,
            1'b0, 1'b0, 1'b0, 1'b0, 1'b0
        );
        check_controls(
            "AUIPC", encode_u(7'b0010111),
            ALU_ADD, IMM_U, BR_NONE, WB_ALU, MEM_WORD,
            1'b1, 1'b1, 1'b1, 1'b0, 1'b0,
            1'b0, 1'b0, 1'b0, 1'b0, 1'b0
        );
        check_controls(
            "JAL", 32'h0080_01ef,
            ALU_ADD, IMM_J, BR_NONE, WB_PC4, MEM_WORD,
            1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
            1'b0, 1'b1, 1'b0, 1'b0, 1'b0
        );
        check_controls(
            "JALR", encode_i(12'd8, 3'b000, 7'b1100111),
            ALU_ADD, IMM_I, BR_NONE, WB_PC4, MEM_WORD,
            1'b1, 1'b1, 1'b0, 1'b0, 1'b0,
            1'b0, 1'b1, 1'b1, 1'b0, 1'b0
        );

        // Branches, in architectural-table order
        check_controls("BEQ",  encode_b(3'b000), ALU_ADD, IMM_B, BR_EQ,  WB_ALU, MEM_WORD, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_controls("BNE",  encode_b(3'b001), ALU_ADD, IMM_B, BR_NE,  WB_ALU, MEM_WORD, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_controls("BLT",  encode_b(3'b100), ALU_ADD, IMM_B, BR_LT,  WB_ALU, MEM_WORD, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_controls("BGE",  encode_b(3'b101), ALU_ADD, IMM_B, BR_GE,  WB_ALU, MEM_WORD, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_controls("BLTU", encode_b(3'b110), ALU_ADD, IMM_B, BR_LTU, WB_ALU, MEM_WORD, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_controls("BGEU", encode_b(3'b111), ALU_ADD, IMM_B, BR_GEU, WB_ALU, MEM_WORD, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

        // Loads
        check_controls("LB",  encode_i(12'd4, 3'b000, 7'b0000011), ALU_ADD, IMM_I, BR_NONE, WB_MEM, MEM_BYTE, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_controls("LH",  encode_i(12'd4, 3'b001, 7'b0000011), ALU_ADD, IMM_I, BR_NONE, WB_MEM, MEM_HALF, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_controls("LW",  encode_i(12'd4, 3'b010, 7'b0000011), ALU_ADD, IMM_I, BR_NONE, WB_MEM, MEM_WORD, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_controls("LBU", encode_i(12'd4, 3'b100, 7'b0000011), ALU_ADD, IMM_I, BR_NONE, WB_MEM, MEM_BYTE, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);
        check_controls("LHU", encode_i(12'd4, 3'b101, 7'b0000011), ALU_ADD, IMM_I, BR_NONE, WB_MEM, MEM_HALF, 1'b1, 1'b1, 1'b0, 1'b1, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0);

        // Stores
        check_controls("SB", encode_s(3'b000), ALU_ADD, IMM_S, BR_NONE, WB_ALU, MEM_BYTE, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_controls("SH", encode_s(3'b001), ALU_ADD, IMM_S, BR_NONE, WB_ALU, MEM_HALF, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_controls("SW", encode_s(3'b010), ALU_ADD, IMM_S, BR_NONE, WB_ALU, MEM_WORD, 1'b0, 1'b1, 1'b0, 1'b0, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

        // Immediate ALU instructions
        check_alu_imm("ADDI",  encode_i(12'h001, 3'b000, 7'b0010011), ALU_ADD);
        check_alu_imm("SLTI",  encode_i(12'h001, 3'b010, 7'b0010011), ALU_SLT);
        check_alu_imm("SLTIU", encode_i(12'h001, 3'b011, 7'b0010011), ALU_SLTU);
        check_alu_imm("XORI",  encode_i(12'h001, 3'b100, 7'b0010011), ALU_XOR);
        check_alu_imm("ORI",   encode_i(12'h001, 3'b110, 7'b0010011), ALU_OR);
        check_alu_imm("ANDI",  encode_i(12'h001, 3'b111, 7'b0010011), ALU_AND);
        check_alu_imm("SLLI",  encode_i({7'b0000000, 5'd3}, 3'b001, 7'b0010011), ALU_SLL);
        check_alu_imm("SRLI",  encode_i({7'b0000000, 5'd3}, 3'b101, 7'b0010011), ALU_SRL);
        check_alu_imm("SRAI",  encode_i({7'b0100000, 5'd3}, 3'b101, 7'b0010011), ALU_SRA);

        // Register-register ALU instructions
        check_alu_reg("ADD",  encode_r(7'b0000000, 3'b000), ALU_ADD);
        check_alu_reg("SUB",  encode_r(7'b0100000, 3'b000), ALU_SUB);
        check_alu_reg("SLL",  encode_r(7'b0000000, 3'b001), ALU_SLL);
        check_alu_reg("SLT",  encode_r(7'b0000000, 3'b010), ALU_SLT);
        check_alu_reg("SLTU", encode_r(7'b0000000, 3'b011), ALU_SLTU);
        check_alu_reg("XOR",  encode_r(7'b0000000, 3'b100), ALU_XOR);
        check_alu_reg("SRL",  encode_r(7'b0000000, 3'b101), ALU_SRL);
        check_alu_reg("SRA",  encode_r(7'b0100000, 3'b101), ALU_SRA);
        check_alu_reg("OR",   encode_r(7'b0000000, 3'b110), ALU_OR);
        check_alu_reg("AND",  encode_r(7'b0000000, 3'b111), ALU_AND);

        // RV32M register-register instructions. funct7 selects the M extension
        // and funct3 selects the exact multiply/divide operation.
        check_muldiv("MUL",    3'b000, MULDIV_MUL);
        check_muldiv("MULH",   3'b001, MULDIV_MULH);
        check_muldiv("MULHSU", 3'b010, MULDIV_MULHSU);
        check_muldiv("MULHU",  3'b011, MULDIV_MULHU);
        check_muldiv("DIV",    3'b100, MULDIV_DIV);
        check_muldiv("DIVU",   3'b101, MULDIV_DIVU);
        check_muldiv("REM",    3'b110, MULDIV_REM);
        check_muldiv("REMU",   3'b111, MULDIV_REMU);

        // FENCE instructions are currently decoded as no-ops.
        check_controls("FENCE",   32'h0000_000f, ALU_ADD, IMM_I, BR_NONE, WB_ALU, MEM_WORD, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_controls("FENCE.I", 32'h0000_100f, ALU_ADD, IMM_I, BR_NONE, WB_ALU, MEM_WORD, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_controls("FENCE reserved fields ignored", 32'hf00f_8f8f, ALU_ADD, IMM_I, BR_NONE, WB_ALU, MEM_WORD, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);
        check_controls("FENCE.I reserved fields ignored", 32'habcd_9f8f, ALU_ADD, IMM_I, BR_NONE, WB_ALU, MEM_WORD, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0);

        // Environment instructions
        check_controls("ECALL",  32'h0000_0073, ALU_ADD, IMM_I, BR_NONE, WB_ALU, MEM_WORD, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);
        check_controls("EBREAK", 32'h0010_0073, ALU_ADD, IMM_I, BR_NONE, WB_ALU, MEM_WORD, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 1'b1, 1'b0);

        // Unsupported and malformed encodings
        check_illegal("unknown opcode", 32'hffff_ffff);
        check_illegal("invalid JALR funct3", encode_i(12'd0, 3'b001, 7'b1100111));
        check_illegal("invalid branch funct3", encode_b(3'b010));
        check_illegal("invalid load funct3", encode_i(12'd0, 3'b011, 7'b0000011));
        check_illegal("invalid store funct3", encode_s(3'b011));
        check_illegal("invalid immediate shift funct7", encode_i({7'b0000001, 5'd0}, 3'b001, 7'b0010011));
        check_illegal("invalid FENCE funct3", encode_i(12'd0, 3'b010, 7'b0001111));
        check_illegal("unsupported SYSTEM instruction", 32'h0020_0073);

        // Random stimulus supplements the exhaustive directed instruction list.
        // Each random test is still checked against an independently selected
        // expected control operation.
        for (int i = 0; i < NUM_RANDOM_TESTS; i++) begin
            logic [31:0] random_instruction;
            logic [11:0] random_imm;
            logic [6:0] random_funct7;
            logic [2:0] random_funct3;
            logic [3:0] expected_random_alu_op;
            logic [2:0] expected_random_branch_op;

            random_imm = $urandom;

            case ($urandom_range(0, 4))
                0: begin
                    random_instruction = encode_i(random_imm, 3'b000, OP_IMM);
                    check_alu_imm(
                        $sformatf("random ADDI %0d", i),
                        random_instruction,
                        ALU_ADD
                    );
                end

                1: begin
                    case ($urandom_range(0, 5))
                        0: begin
                            random_funct3 = 3'b000;
                            expected_random_branch_op = BR_EQ;
                        end
                        1: begin
                            random_funct3 = 3'b001;
                            expected_random_branch_op = BR_NE;
                        end
                        2: begin
                            random_funct3 = 3'b100;
                            expected_random_branch_op = BR_LT;
                        end
                        3: begin
                            random_funct3 = 3'b101;
                            expected_random_branch_op = BR_GE;
                        end
                        4: begin
                            random_funct3 = 3'b110;
                            expected_random_branch_op = BR_LTU;
                        end
                        default: begin
                            random_funct3 = 3'b111;
                            expected_random_branch_op = BR_GEU;
                        end
                    endcase

                    check_controls(
                        $sformatf("random branch %0d", i),
                        encode_b(random_funct3),
                        ALU_ADD, IMM_B, expected_random_branch_op,
                        WB_ALU, MEM_WORD,
                        1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                        1'b0, 1'b0, 1'b0, 1'b0, 1'b0
                    );
                end

                2: begin
                    case ($urandom_range(0, 9))
                        0: begin
                            random_funct7 = 7'b0000000;
                            random_funct3 = 3'b000;
                            expected_random_alu_op = ALU_ADD;
                        end
                        1: begin
                            random_funct7 = 7'b0100000;
                            random_funct3 = 3'b000;
                            expected_random_alu_op = ALU_SUB;
                        end
                        2: begin
                            random_funct7 = 7'b0000000;
                            random_funct3 = 3'b001;
                            expected_random_alu_op = ALU_SLL;
                        end
                        3: begin
                            random_funct7 = 7'b0000000;
                            random_funct3 = 3'b010;
                            expected_random_alu_op = ALU_SLT;
                        end
                        4: begin
                            random_funct7 = 7'b0000000;
                            random_funct3 = 3'b011;
                            expected_random_alu_op = ALU_SLTU;
                        end
                        5: begin
                            random_funct7 = 7'b0000000;
                            random_funct3 = 3'b100;
                            expected_random_alu_op = ALU_XOR;
                        end
                        6: begin
                            random_funct7 = 7'b0000000;
                            random_funct3 = 3'b101;
                            expected_random_alu_op = ALU_SRL;
                        end
                        7: begin
                            random_funct7 = 7'b0100000;
                            random_funct3 = 3'b101;
                            expected_random_alu_op = ALU_SRA;
                        end
                        8: begin
                            random_funct7 = 7'b0000000;
                            random_funct3 = 3'b110;
                            expected_random_alu_op = ALU_OR;
                        end
                        default: begin
                            random_funct7 = 7'b0000000;
                            random_funct3 = 3'b111;
                            expected_random_alu_op = ALU_AND;
                        end
                    endcase

                    check_alu_reg(
                        $sformatf("random register ALU %0d", i),
                        encode_r(random_funct7, random_funct3),
                        expected_random_alu_op
                    );
                end

                3: begin
                    random_instruction = $urandom;
                    while (known_opcode(random_instruction[6:0])) begin
                        random_instruction = $urandom;
                    end
                    check_illegal(
                        $sformatf("random unknown opcode %0d", i),
                        random_instruction
                    );
                end

                default: begin
                    random_funct3 = $urandom_range(0, 7);
                    check_muldiv(
                        $sformatf("random RV32M operation %0d", i),
                        random_funct3,
                        muldiv_op_t'(random_funct3)
                    );
                end
            endcase
        end

        if ((legal_tests == 0) || (illegal_tests == 0)) begin
            $error(
                "Decoder did not cover both legal and illegal instructions: legal=%0d illegal=%0d",
                legal_tests,
                illegal_tests
            );
            errors++;
        end

        if ((opcode_hits[OP_LUI]    == 0) ||
            (opcode_hits[OP_AUIPC]  == 0) ||
            (opcode_hits[OP_JAL]    == 0) ||
            (opcode_hits[OP_JALR]   == 0) ||
            (opcode_hits[OP_BRANCH] == 0) ||
            (opcode_hits[OP_LOAD]   == 0) ||
            (opcode_hits[OP_STORE]  == 0) ||
            (opcode_hits[OP_IMM]    == 0) ||
            (opcode_hits[OP_REG]    == 0) ||
            (opcode_hits[OP_FENCE]  == 0) ||
            (opcode_hits[OP_SYSTEM] == 0)) begin
            $error("One or more supported decoder opcode families were not tested");
            errors++;
        end

        $display(
            "decoder_tb coverage summary: %0d legal tests, %0d illegal tests",
            legal_tests,
            illegal_tests
        );

        if (errors == 0) begin
            $display("PASS: decoder_tb");
        end else begin
            $fatal(1, "FAIL: decoder_tb completed with %0d error(s)", errors);
        end
    end
endmodule

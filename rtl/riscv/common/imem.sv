// Instruction memory.
//
// The memory array is word-organized, but the interface uses byte addresses.
// Each RV32I instruction occupies 4 bytes, so byte addresses 0, 4, 8, and 12
// select mem[0], mem[1], mem[2], and mem[3]. Therefore:
//   - address[31:2] selects the instruction word.
//   - address[1:0] must be 2'b00 for an aligned RV32I instruction fetch.
//
// Uninitialized, misaligned, and out-of-range locations return the canonical
// RV32I NOP. Invalid addresses also assert access_fault.

module imem #(
    parameter int WORDS = 256,  // 1KB = 1024 Bytes / 4 Bytes = 256 words
    parameter string HEX_FILE = ""
) (
    input  logic [31:0] address,
    output logic [31:0] instruction,
    output logic        access_fault
);
    import rv32i_pkg::*;

    logic [31:0] mem[0:WORDS-1];

    initial begin
        // Initialize every location to NOP so a short hex file does not leave
        // unknown instructions in the unused portion of memory.
        for (int i = 0; i < WORDS; i++) begin
            mem[i] = INSTRUCTION_NOP;
        end

        // A hex image is optional, which keeps the module easy to reuse in
        // small unit tests that directly initialize memory.
        if (HEX_FILE != "") begin
            $readmemh(HEX_FILE, mem);
        end
    end

    always_comb begin
        // Defaulting to NOP keeps a bad fetch from propagating X values while
        // access_fault tells the core that the address was not valid.
        instruction = INSTRUCTION_NOP;
        access_fault = (address[1:0] != 2'b00) || (address[31:2] >= WORDS);

        if (!access_fault) begin
            instruction = mem[address[31:2]];
        end
    end

endmodule

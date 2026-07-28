// Data memory.
//
// The interface is byte-addressed while the internal array stores 32-bit
// words. addr[1:0] selects a byte lane within the word. Loads are asynchronous,
// and stores update memory on the rising clock edge. Invalid encodings,
// misaligned accesses, and out-of-range requests assert access_fault.

module dmem #(
    parameter int WIDTH = 32,
    parameter int DEPTH = 1024,
    parameter string MEM_INIT = ""
) (
    input  logic             clk,
    input  logic [WIDTH-1:0] addr,
    input  logic [WIDTH-1:0] wr_data,
    input  logic [      2:0] funct3,
    input  logic             mem_read,
    input  logic             mem_write,
    output logic [WIDTH-1:0] rd_data,
    output logic             access_fault
);
    import rv32i_pkg::*;

    localparam int ADDR_WIDTH = $clog2(DEPTH);

    logic [WIDTH-1:0] mem[0:DEPTH-1];
    logic [ADDR_WIDTH-1:0] word_addr;
    logic [1:0] byte_off;
    logic [WIDTH-1:0] word;
    logic address_valid;
    logic request;
    logic encoding_valid;
    logic address_aligned;

    initial begin
        // Give simulation a deterministic starting state before optionally
        // loading a program-specific data image.
        for (int i = 0; i < DEPTH; i++) begin
            mem[i] = '0;
        end

        if (MEM_INIT != "") begin
            $readmemh(MEM_INIT, mem);
        end
    end

    // Split the byte address into its word index and byte-lane offset.
    assign word_addr = addr[ADDR_WIDTH+1:2];
    assign byte_off = addr[1:0];
    assign address_valid = (addr[WIDTH-1:2] < DEPTH);
    assign word = address_valid ? mem[word_addr] : '0;
    assign request = mem_read || mem_write;

    // A valid request must be exactly one load or one store with a supported
    // RV32I funct3 encoding. Simultaneous read and write is rejected.
    always_comb begin
        encoding_valid = 1'b0;

        if (mem_read && !mem_write) begin
            case (funct3)
                LOAD_BYTE,
                LOAD_HALF,
                LOAD_WORD,
                LOAD_BYTE_U,
                LOAD_HALF_U: encoding_valid = 1'b1;
                default: encoding_valid = 1'b0;
            endcase
        end else if (mem_write && !mem_read) begin
            case (funct3)
                STORE_BYTE,
                STORE_HALF,
                STORE_WORD: encoding_valid = 1'b1;
                default: encoding_valid = 1'b0;
            endcase
        end
    end

    // Bytes may use any offset, halfwords require addr[0] = 0, and words
    // require addr[1:0] = 2'b00.
    always_comb begin
        case (funct3[1:0])
            2'b00: address_aligned = 1'b1;
            2'b01: address_aligned = (addr[0] == 1'b0);
            2'b10: address_aligned = (addr[1:0] == 2'b00);
            default: address_aligned = 1'b0;
        endcase
    end

    assign access_fault = request &&
                          (!address_valid || !address_aligned || !encoding_valid);

    // Select the requested byte or halfword and perform the sign or zero
    // extension required by the load instruction.
    always_comb begin
        rd_data = '0;

        if (mem_read && !access_fault) begin
            case (funct3)
                LOAD_BYTE: begin
                    case (byte_off)
                        2'd0: rd_data = {{24{word[7]}}, word[7:0]};
                        2'd1: rd_data = {{24{word[15]}}, word[15:8]};
                        2'd2: rd_data = {{24{word[23]}}, word[23:16]};
                        2'd3: rd_data = {{24{word[31]}}, word[31:24]};
                    endcase
                end

                LOAD_BYTE_U: begin
                    case (byte_off)
                        2'd0: rd_data = {24'd0, word[7:0]};
                        2'd1: rd_data = {24'd0, word[15:8]};
                        2'd2: rd_data = {24'd0, word[23:16]};
                        2'd3: rd_data = {24'd0, word[31:24]};
                    endcase
                end

                LOAD_HALF: begin
                    case (byte_off[1])
                        1'b0: rd_data = {{16{word[15]}}, word[15:0]};
                        1'b1: rd_data = {{16{word[31]}}, word[31:16]};
                    endcase
                end

                LOAD_HALF_U: begin
                    case (byte_off[1])
                        1'b0: rd_data = {16'd0, word[15:0]};
                        1'b1: rd_data = {16'd0, word[31:16]};
                    endcase
                end

                LOAD_WORD: rd_data = word;
                default: rd_data = '0;
            endcase
        end
    end

    // A standard clocked block permits the separate initial block to preload
    // the array. always_ff would reject the two procedural writers in Questa.
    always @(posedge clk) begin
        if (mem_write && !access_fault) begin
            // Partial stores preserve every byte lane not selected by funct3
            // and byte_off.
            case (funct3)
                STORE_BYTE: begin
                    case (byte_off)
                        2'd0: mem[word_addr][7:0] <= wr_data[7:0];
                        2'd1: mem[word_addr][15:8] <= wr_data[7:0];
                        2'd2: mem[word_addr][23:16] <= wr_data[7:0];
                        2'd3: mem[word_addr][31:24] <= wr_data[7:0];
                    endcase
                end

                STORE_HALF: begin
                    case (byte_off[1])
                        1'b0: mem[word_addr][15:0] <= wr_data[15:0];
                        1'b1: mem[word_addr][31:16] <= wr_data[15:0];
                    endcase
                end

                STORE_WORD: mem[word_addr] <= wr_data;
                default: begin end
            endcase
        end
    end

endmodule

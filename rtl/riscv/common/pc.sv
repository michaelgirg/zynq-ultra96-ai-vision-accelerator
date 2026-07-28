// Program counter register
//
// The next-PC logic is implemented outside this module since
// a branch or jump can provide a different address.

module pc #(
    parameter logic [31:0] RST_PC = 32'h0000_0000
) (
    input  logic        clk,
    input  logic        rst,
    input  logic        en,
    input  logic [31:0] next_pc,
    output logic [31:0] pc
);

    always_ff @(posedge clk) begin
        if (rst) begin
            pc <= RST_PC;
        end else if (en) begin
            pc <= next_pc;
        end
    end

endmodule

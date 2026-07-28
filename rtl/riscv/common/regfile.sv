// 32-register RV32I register file with two asynchronous read ports and one
// synchronous write port. Architectural register x0 always reads as zero and
// ignores writes.

module regfile #(
    parameter int WIDTH = 32,  //width of each register, typically 32 bits for RV32I
    parameter int DEPTH = 32   // number of registers, typically 32 for RV32I (x0 to x31)
) (
    input  logic                     clk,
    input  logic [$clog2(DEPTH)-1:0] rs1_addr,
    input  logic [$clog2(DEPTH)-1:0] rs2_addr,
    output logic [        WIDTH-1:0] rs1_data,
    output logic [        WIDTH-1:0] rs2_data,
    input  logic [$clog2(DEPTH)-1:0] rd_addr,
    input  logic [        WIDTH-1:0] rd_data,
    input  logic                     we
);

    logic [WIDTH-1:0] regs[0:DEPTH-1];

    initial begin
        for (int i = 0; i < DEPTH; i++) begin
            regs[i] = '0;
        end
    end

    always @(posedge clk) begin
        if (we && (rd_addr != '0)) begin
            regs[rd_addr] <= rd_data;
        end
    end

    assign rs1_data = (rs1_addr == '0) ? '0 : regs[rs1_addr];
    assign rs2_data = (rs2_addr == '0) ? '0 : regs[rs2_addr];

endmodule

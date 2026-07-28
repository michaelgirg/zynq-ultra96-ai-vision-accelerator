import rv32i_pkg::*;

// Data forwarding unit.
//
// Forwarding avoids unnecessary stalls by taking a recently calculated value
// directly from a later pipeline stage instead of waiting for it to be written
// into the register file.
//
// Selection values:
// 2'b00: use the original value read from the register file
// 2'b01: forward the value from the MEM/WB stage
// 2'b10: forward the value from the EX/MEM stage
//
// EX/MEM has priority because it contains the newer instruction.

module forwarding_unit (
    // Source registers used by the instruction currently in Execute.
    input logic [4:0] rs1_addr,
    input logic [4:0] rs2_addr,

    // Instructions currently in later pipeline stages.
    input var ex_mem_t ex_mem_data,
    input var mem_wb_t mem_wb_data,

    // Select signals for the forwarding muxes.
    output logic [1:0] forward_a,
    output logic [1:0] forward_b
);

    always_comb begin
        // Default: use the values originally read from the register file.
        forward_a = 2'b00;
        forward_b = 2'b00;

        // Check MEM/WB first. EX/MEM is checked afterward so it can override
        // this selection when both stages write the same register.
        // Do not forward x0 because x0 is always hardwired to zero.
        if (mem_wb_data.valid && mem_wb_data.reg_write && (mem_wb_data.rd_addr != 5'd0)) begin
            // If MEM/WB writes the same register that the current instruction
            // needs, tell the ALU-input mux to use the MEM/WB value.
            if (mem_wb_data.rd_addr == rs1_addr) forward_a = 2'b01;
            if (mem_wb_data.rd_addr == rs2_addr) forward_b = 2'b01;
        end

        // Forward from EX/MEM when it contains the newest required result.
        // A load cannot forward from EX/MEM because alu_result is only its
        // memory address. The loaded value becomes available in MEM/WB.
        if (ex_mem_data.valid && ex_mem_data.reg_write && !ex_mem_data.mem_read && (ex_mem_data.rd_addr != 5'd0)) begin
            if (ex_mem_data.rd_addr == rs1_addr) forward_a = 2'b10;
            if (ex_mem_data.rd_addr == rs2_addr) forward_b = 2'b10;
        end
    end

endmodule

package soc_address_map_pkg;

    localparam logic [31:0] LOCAL_MEMORY_BASE = 32'h0000_0000;
    localparam logic [31:0] LOCAL_MEMORY_SIZE = 32'h0001_0000;

    localparam logic [31:0] VISION_ACCEL_BASE = 32'ha000_0000;
    localparam logic [31:0] VISION_ACCEL_SIZE = 32'h0000_1000;

    localparam logic [31:0] AXI_DMA_BASE = 32'ha001_0000;
    localparam logic [31:0] AXI_DMA_SIZE = 32'h0001_0000;

    localparam logic [31:0] MAILBOX_BASE = 32'ha002_0000;
    localparam logic [31:0] MAILBOX_SIZE = 32'h0000_1000;

    // These two windows are visible to the ARM host portal, not to RV32 MMIO.
    localparam logic [31:0] HOST_IMEM_BASE = 32'ha003_0000;
    localparam logic [31:0] HOST_IMEM_SIZE = 32'h0001_0000;
    localparam logic [31:0] HOST_DMEM_BASE = 32'ha004_0000;
    localparam logic [31:0] HOST_DMEM_SIZE = 32'h0001_0000;

    function automatic logic address_in_range(
        input logic [31:0] address,
        input logic [31:0] base,
        input logic [31:0] size
    );
        address_in_range = (address >= base) && (address < (base + size));
    endfunction

    function automatic logic is_local_data_address(input logic [31:0] address);
        is_local_data_address = address_in_range(
            address, LOCAL_MEMORY_BASE, LOCAL_MEMORY_SIZE
        );
    endfunction

    function automatic logic is_rv_mmio_address(input logic [31:0] address);
        is_rv_mmio_address =
            address_in_range(address, VISION_ACCEL_BASE, VISION_ACCEL_SIZE) ||
            address_in_range(address, AXI_DMA_BASE, AXI_DMA_SIZE) ||
            address_in_range(address, MAILBOX_BASE, MAILBOX_SIZE);
    endfunction

endpackage

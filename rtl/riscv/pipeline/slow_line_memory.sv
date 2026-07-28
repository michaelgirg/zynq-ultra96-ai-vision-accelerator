// slow_line_memory.sv -- serialized cache-line backing memory
//
// A single synchronous 32-bit RAM port services both cache-line transfers and
// ARM host accesses. Cache lines are serialized one word per clock so Vivado
// can infer block RAM instead of dissolving a mixed-width memory into flops.

module slow_line_memory #(
    parameter int ADDR_WIDTH  = 32,
    parameter int DATA_WIDTH  = 32,
    parameter int LINE_WORDS  = 4,
    parameter int DEPTH_WORDS = 1024,
    parameter int LATENCY     = 15,
    parameter string HEX_FILE = ""
) (
    input logic clk,
    input logic rst,

    input  logic                               req_valid,
    output logic                               req_ready,
    input  logic                               req_write,
    input  logic [ADDR_WIDTH-1:0]              req_addr,
    input  logic [(DATA_WIDTH*LINE_WORDS)-1:0] req_wdata,

    output logic                               resp_valid,
    input  logic                               resp_ready,
    output logic [(DATA_WIDTH*LINE_WORDS)-1:0] resp_rdata,
    output logic                               resp_fault,

    input  logic                      host_req_valid,
    output logic                      host_req_ready,
    input  logic                      host_req_write,
    input  logic [ADDR_WIDTH-1:0]     host_req_addr,
    input  logic [DATA_WIDTH-1:0]     host_req_wdata,
    input  logic [(DATA_WIDTH/8)-1:0] host_req_wstrb,
    output logic                      host_resp_valid,
    input  logic                      host_resp_ready,
    output logic [DATA_WIDTH-1:0]     host_resp_rdata,
    output logic                      host_resp_fault
);

    localparam int BYTES_PER_WORD = DATA_WIDTH / 8;
    localparam int LINE_BYTES = LINE_WORDS * BYTES_PER_WORD;
    localparam int LINE_BITS = DATA_WIDTH * LINE_WORDS;
    localparam int BYTE_OFFSET_BITS = $clog2(BYTES_PER_WORD);
    localparam int LINE_OFFSET_BITS = $clog2(LINE_BYTES);
    localparam int WORD_INDEX_BITS = (DEPTH_WORDS <= 1) ? 1 : $clog2(DEPTH_WORDS);
    localparam int WORD_COUNT_BITS = (LINE_WORDS <= 1) ? 1 : $clog2(LINE_WORDS + 1);
    // One issue cycle plus LINE_WORDS synchronous capture cycles are required.
    localparam int MIN_LINE_LATENCY = LINE_WORDS + 1;
    localparam int EFFECTIVE_LATENCY =
        (LATENCY < MIN_LINE_LATENCY) ? MIN_LINE_LATENCY : LATENCY;
    localparam int COUNT_BITS = $clog2(EFFECTIVE_LATENCY + 1);

    typedef enum logic [2:0] {
        MEMORY_IDLE,
        MEMORY_HOST_WAIT,
        MEMORY_HOST_RESPONSE,
        MEMORY_CORE_WAIT,
        MEMORY_CORE_RESPONSE
    } memory_state_t;

    memory_state_t state;

    (* ram_style = "block" *) logic [DATA_WIDTH-1:0] mem [0:DEPTH_WORDS-1];

    logic ram_enable;
    logic ram_write;
    logic [WORD_INDEX_BITS-1:0] ram_addr;
    logic [DATA_WIDTH-1:0] ram_wdata;
    logic [BYTES_PER_WORD-1:0] ram_wstrb;
    logic [DATA_WIDTH-1:0] ram_rdata;

    logic pending_write;
    logic pending_host_write;
    logic pending_fault;
    logic [WORD_INDEX_BITS-1:0] pending_base_word;
    logic [LINE_BITS-1:0] pending_wdata;
    logic [LINE_BITS-1:0] pending_read_line;
    logic [WORD_COUNT_BITS-1:0] issued_words;
    logic [WORD_COUNT_BITS-1:0] captured_words;
    logic [COUNT_BITS-1:0] cycles_left;

    logic [WORD_INDEX_BITS-1:0] request_base_word;
    logic [WORD_INDEX_BITS-1:0] host_word_index;
    logic request_is_fault;
    logic host_request_fault;

    assign req_ready = (state == MEMORY_IDLE) && !host_req_valid;
    assign host_req_ready = (state == MEMORY_IDLE);
    assign request_base_word =
        WORD_INDEX_BITS'($unsigned(req_addr) >> BYTE_OFFSET_BITS);
    assign host_word_index =
        WORD_INDEX_BITS'($unsigned(host_req_addr) >> BYTE_OFFSET_BITS);
    assign request_is_fault =
        (req_addr[LINE_OFFSET_BITS-1:0] != '0) ||
        (($unsigned(req_addr) >> BYTE_OFFSET_BITS) >
         (DEPTH_WORDS - LINE_WORDS));
    assign host_request_fault =
        (host_req_addr[BYTE_OFFSET_BITS-1:0] != '0) ||
        (($unsigned(host_req_addr) >> BYTE_OFFSET_BITS) >= DEPTH_WORDS);

    initial begin
        if (DATA_WIDTH != 32) $fatal(1, "DATA_WIDTH must be 32");
        if (LINE_WORDS < 2) $fatal(1, "LINE_WORDS must be at least two");
        if ((LINE_WORDS & (LINE_WORDS - 1)) != 0)
            $fatal(1, "LINE_WORDS must be a power of two");
        if (DEPTH_WORDS < LINE_WORDS)
            $fatal(1, "DEPTH_WORDS must contain at least one line");
        if ((DEPTH_WORDS % LINE_WORDS) != 0)
            $fatal(1, "DEPTH_WORDS must be a multiple of LINE_WORDS");
        if (LATENCY < 1) $fatal(1, "LATENCY must be at least one cycle");

        for (int word = 0; word < DEPTH_WORDS; word++) mem[word] = '0;
        if (HEX_FILE != "") $readmemh(HEX_FILE, mem);
    end

    // This is the only RTL process that writes or reads the memory array. The
    // registered output, single address, enable, and byte write enables match
    // a native FPGA block-RAM port.
    always @(posedge clk) begin
        if (ram_enable) begin
            if (ram_write) begin
                for (int byte_index = 0; byte_index < BYTES_PER_WORD; byte_index++) begin
                    if (ram_wstrb[byte_index]) begin
                        mem[ram_addr][byte_index*8 +: 8] <=
                            ram_wdata[byte_index*8 +: 8];
                    end
                end
            end
            ram_rdata <= mem[ram_addr];
        end
    end

    always_comb begin
        ram_enable = 1'b0;
        ram_write = 1'b0;
        ram_addr = '0;
        ram_wdata = '0;
        ram_wstrb = '0;

        if (state == MEMORY_IDLE) begin
            if (host_req_valid && host_req_ready && !host_request_fault) begin
                ram_enable = 1'b1;
                ram_write = host_req_write;
                ram_addr = host_word_index;
                ram_wdata = host_req_wdata;
                ram_wstrb = host_req_wstrb;
            end
            else if (req_valid && req_ready && !request_is_fault) begin
                ram_enable = 1'b1;
                ram_write = req_write;
                ram_addr = request_base_word;
                ram_wdata = req_wdata[0 +: DATA_WIDTH];
                ram_wstrb = {BYTES_PER_WORD{1'b1}};
            end
        end
        else if (state == MEMORY_CORE_WAIT &&
                 !pending_fault && issued_words < LINE_WORDS) begin
            ram_enable = 1'b1;
            ram_write = pending_write;
            ram_addr = pending_base_word + WORD_INDEX_BITS'(issued_words);
            ram_wdata = pending_wdata[issued_words*DATA_WIDTH +: DATA_WIDTH];
            ram_wstrb = {BYTES_PER_WORD{1'b1}};
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            state <= MEMORY_IDLE;
            pending_write <= 1'b0;
            pending_host_write <= 1'b0;
            pending_fault <= 1'b0;
            pending_base_word <= '0;
            pending_wdata <= '0;
            pending_read_line <= '0;
            issued_words <= '0;
            captured_words <= '0;
            cycles_left <= '0;
            resp_valid <= 1'b0;
            resp_rdata <= '0;
            resp_fault <= 1'b0;
            host_resp_valid <= 1'b0;
            host_resp_rdata <= '0;
            host_resp_fault <= 1'b0;
        end
        else begin
            case (state)
                MEMORY_IDLE: begin
                    if (host_req_valid && host_req_ready) begin
                        pending_host_write <= host_req_write;
                        host_resp_fault <= host_request_fault;
                        host_resp_rdata <= '0;
                        state <= MEMORY_HOST_WAIT;
                    end
                    else if (req_valid && req_ready) begin
                        pending_write <= req_write;
                        pending_fault <= request_is_fault;
                        pending_base_word <= request_base_word;
                        pending_wdata <= req_wdata;
                        pending_read_line <= '0;
                        issued_words <= request_is_fault ? '0 : WORD_COUNT_BITS'(1);
                        captured_words <= '0;
                        cycles_left <= COUNT_BITS'(EFFECTIVE_LATENCY);
                        state <= MEMORY_CORE_WAIT;
                    end
                end

                MEMORY_HOST_WAIT: begin
                    if (!host_resp_fault && !pending_host_write)
                        host_resp_rdata <= ram_rdata;
                    host_resp_valid <= 1'b1;
                    state <= MEMORY_HOST_RESPONSE;
                end

                MEMORY_HOST_RESPONSE: begin
                    if (host_resp_valid && host_resp_ready) begin
                        host_resp_valid <= 1'b0;
                        host_resp_fault <= 1'b0;
                        state <= MEMORY_IDLE;
                    end
                end

                MEMORY_CORE_WAIT: begin
                    if (!pending_fault && !pending_write &&
                        captured_words < issued_words) begin
                        pending_read_line[captured_words*DATA_WIDTH +: DATA_WIDTH] <=
                            ram_rdata;
                        captured_words <= captured_words + 1'b1;
                    end
                    if (!pending_fault && issued_words < LINE_WORDS)
                        issued_words <= issued_words + 1'b1;

                    if (cycles_left > COUNT_BITS'(1)) begin
                        cycles_left <= cycles_left - 1'b1;
                    end
                    else if (pending_write) begin
                        state <= MEMORY_IDLE;
                    end
                    else begin
                        resp_valid <= 1'b1;
                        resp_rdata <= pending_fault ? '0 : pending_read_line;
                        resp_fault <= pending_fault;
                        state <= MEMORY_CORE_RESPONSE;
                    end
                end

                MEMORY_CORE_RESPONSE: begin
                    if (resp_valid && resp_ready) begin
                        resp_valid <= 1'b0;
                        resp_fault <= 1'b0;
                        state <= MEMORY_IDLE;
                    end
                end

                default: begin
                    resp_valid <= 1'b0;
                    host_resp_valid <= 1'b0;
                    state <= MEMORY_IDLE;
                end
            endcase
        end
    end

endmodule

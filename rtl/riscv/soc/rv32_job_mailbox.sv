module rv32_job_mailbox #(
    parameter int C_S_AXI_ADDR_WIDTH = 12
) (
    input  logic                              S_AXI_ACLK,
    input  logic                              S_AXI_ARESETN,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_AWADDR,
    input  logic [2:0]                        S_AXI_AWPROT,
    input  logic                              S_AXI_AWVALID,
    output logic                              S_AXI_AWREADY,
    input  logic [31:0]                       S_AXI_WDATA,
    input  logic [3:0]                        S_AXI_WSTRB,
    input  logic                              S_AXI_WVALID,
    output logic                              S_AXI_WREADY,
    output logic [1:0]                        S_AXI_BRESP,
    output logic                              S_AXI_BVALID,
    input  logic                              S_AXI_BREADY,
    input  logic [C_S_AXI_ADDR_WIDTH-1:0]     S_AXI_ARADDR,
    input  logic [2:0]                        S_AXI_ARPROT,
    input  logic                              S_AXI_ARVALID,
    output logic                              S_AXI_ARREADY,
    output logic [31:0]                       S_AXI_RDATA,
    output logic [1:0]                        S_AXI_RRESP,
    output logic                              S_AXI_RVALID,
    input  logic                              S_AXI_RREADY,
    output logic                              rv32_resetn,
    output logic                              irq,
    // Same control-clock domain; sticky bridge diagnostics survive CPU reset.
    input  logic                              axi_timeout,
    input  logic                              axi_quarantined,
    input  logic [31:0]                       axi_fault_addr,
    input  logic [31:0]                       axi_fault_info,
    input  logic [31:0]                       axi_fault_wait
);
    localparam logic [1:0] AXI_OKAY = 2'b00;
    localparam logic [1:0] AXI_SLVERR = 2'b10;

    localparam logic [11:0] ADDR_COMMAND        = 12'h000;
    localparam logic [11:0] ADDR_STATUS         = 12'h004;
    localparam logic [11:0] ADDR_INPUT_ADDR     = 12'h008;
    localparam logic [11:0] ADDR_OUTPUT_ADDR    = 12'h00C;
    localparam logic [11:0] ADDR_TRANSFER_BYTES = 12'h010;
    localparam logic [11:0] ADDR_MODE           = 12'h014;
    localparam logic [11:0] ADDR_THRESHOLD      = 12'h018;
    localparam logic [11:0] ADDR_JOB_ID         = 12'h01C;
    localparam logic [11:0] ADDR_RESULT         = 12'h020;
    localparam logic [11:0] ADDR_ERROR_CODE     = 12'h024;
    localparam logic [11:0] ADDR_MAILBOX_ID     = 12'h028;
    localparam logic [11:0] ADDR_BOOT_CONTROL   = 12'h02C;
    localparam logic [11:0] ADDR_VERSION        = 12'h030;
    localparam logic [11:0] ADDR_IRQ_STATUS     = 12'h034;
    localparam logic [11:0] ADDR_IRQ_ENABLE     = 12'h038;
    localparam logic [11:0] ADDR_DIAG_CONTROL   = 12'h03C;
    localparam logic [11:0] ADDR_SUBMIT_LO      = 12'h040;
    localparam logic [11:0] ADDR_SUBMIT_HI      = 12'h044;
    localparam logic [11:0] ADDR_CLAIM_LO       = 12'h048;
    localparam logic [11:0] ADDR_CLAIM_HI       = 12'h04C;
    localparam logic [11:0] ADDR_END_LO         = 12'h050;
    localparam logic [11:0] ADDR_END_HI         = 12'h054;
    localparam logic [11:0] ADDR_JOB_CYCLES_LO  = 12'h058;
    localparam logic [11:0] ADDR_JOB_CYCLES_HI  = 12'h05C;
    localparam logic [11:0] ADDR_COMPLETED_COUNT = 12'h060;
    localparam logic [11:0] ADDR_FAILED_COUNT   = 12'h064;
    localparam logic [11:0] ADDR_FW_TIMEOUT_COUNT = 12'h068;
    localparam logic [11:0] ADDR_AXI_TIMEOUT_COUNT = 12'h06C;
    localparam logic [11:0] ADDR_FIRST_FAULT_KIND = 12'h070;
    localparam logic [11:0] ADDR_FIRST_FAULT_JOB = 12'h074;
    localparam logic [11:0] ADDR_FIRST_FAULT_CODE = 12'h078;
    localparam logic [11:0] ADDR_FIRST_FAULT_ADDR = 12'h07C;
    localparam logic [11:0] ADDR_FIRST_FAULT_INFO = 12'h080;
    localparam logic [11:0] ADDR_FIRST_FAULT_WAIT = 12'h084;
    localparam logic [11:0] ADDR_FIRST_FAULT_LO  = 12'h088;
    localparam logic [11:0] ADDR_FIRST_FAULT_HI  = 12'h08C;
    localparam logic [11:0] ADDR_AXI_STATUS      = 12'h090;
    localparam logic [11:0] ADDR_AXI_FAULT_ADDR  = 12'h094;
    localparam logic [11:0] ADDR_AXI_FAULT_INFO  = 12'h098;
    localparam logic [11:0] ADDR_AXI_FAULT_WAIT  = 12'h09C;

    localparam logic [31:0] MAILBOX_ID = 32'h5A42_4D42; // "ZBMB"

    localparam logic [31:0] CMD_SUBMIT   = 32'h0000_0001;
    localparam logic [31:0] CMD_CLAIM    = 32'h0000_0002;
    localparam logic [31:0] CMD_COMPLETE = 32'h0000_0004;
    localparam logic [31:0] CMD_FAIL     = 32'h0000_0008;
    localparam logic [31:0] CMD_ACK      = 32'h0000_0010;

    logic aw_captured;
    logic [11:0] awaddr;
    logic w_captured;
    logic [31:0] wdata;
    logic [3:0] wstrb;

    logic pending;
    logic busy;
    logic done;
    logic failed;
    logic [31:0] input_addr;
    logic [31:0] output_addr;
    logic [31:0] transfer_bytes;
    logic [31:0] mode;
    logic [31:0] threshold;
    logic [31:0] job_id;
    logic [31:0] result;
    logic [31:0] error_code;
    logic [2:0] irq_status, irq_enable;
    logic [63:0] clock_count, submit_time, claim_time, end_time, job_cycles;
    logic [31:0] completed_count, failed_count, fw_timeout_count, axi_timeout_count;
    logic [31:0] first_fault_kind, first_fault_job, first_fault_code;
    logic [31:0] first_fault_addr, first_fault_info, first_fault_wait;
    logic [63:0] first_fault_time;
    logic axi_timeout_seen;

    wire idle = !(pending || busy);
    wire terminal = done || failed;
    wire write_fire = aw_captured && w_captured && !S_AXI_BVALID;

    assign S_AXI_AWREADY = !aw_captured && !S_AXI_BVALID;
    assign S_AXI_WREADY = !w_captured && !S_AXI_BVALID;
    assign S_AXI_ARREADY = !S_AXI_RVALID;
    assign irq = |(irq_status & irq_enable);

    function automatic logic [31:0] increment_sat(input logic [31:0] value);
        return (&value) ? value : value + 1'b1;
    endfunction

    function automatic logic address_aligned(input logic [11:0] address);
        return address[1:0] == 2'b00;
    endfunction

    function automatic logic valid_command(input logic [31:0] command);
        case (command)
            CMD_SUBMIT:   valid_command = idle && !terminal && !axi_quarantined && (transfer_bytes != 0);
            CMD_CLAIM:    valid_command = pending;
            CMD_COMPLETE: valid_command = busy;
            CMD_FAIL:     valid_command = busy;
            CMD_ACK:      valid_command = terminal && !busy && !pending;
            default:      valid_command = 1'b0;
        endcase
    endfunction

    function automatic logic valid_write(
        input logic [11:0] address,
        input logic [31:0] data,
        input logic [3:0] strobes
    );
        begin
            if (!address_aligned(address)) begin
                valid_write = 1'b0;
            end
            else if (strobes == 4'b0000) begin
                valid_write = 1'b1;
            end
            else if (strobes != 4'b1111) begin
                valid_write = 1'b0;
            end
            else begin
                case (address)
                    ADDR_COMMAND: valid_write = valid_command(data);
                    ADDR_INPUT_ADDR,
                    ADDR_OUTPUT_ADDR,
                    ADDR_TRANSFER_BYTES,
                    ADDR_MODE,
                    ADDR_THRESHOLD,
                    ADDR_JOB_ID: valid_write = idle && !terminal;
                    ADDR_RESULT,
                    ADDR_ERROR_CODE: valid_write = busy;
                    ADDR_BOOT_CONTROL: valid_write = !data[0] || !axi_quarantined;
                    ADDR_IRQ_STATUS,
                    ADDR_IRQ_ENABLE: valid_write = (data[31:3] == 0);
                    ADDR_DIAG_CONTROL: valid_write = (data == 1) && idle && !terminal && !axi_quarantined;
                    default: valid_write = 1'b0;
                endcase
            end
        end
    endfunction

    function automatic logic valid_read(input logic [11:0] address);
        begin
            if (!address_aligned(address)) begin
                valid_read = 1'b0;
            end
            else begin
                case (address)
                    ADDR_STATUS,
                    ADDR_INPUT_ADDR,
                    ADDR_OUTPUT_ADDR,
                    ADDR_TRANSFER_BYTES,
                    ADDR_MODE,
                    ADDR_THRESHOLD,
                    ADDR_JOB_ID,
                    ADDR_RESULT,
                    ADDR_ERROR_CODE,
                    ADDR_MAILBOX_ID,
                    ADDR_BOOT_CONTROL,
                    ADDR_VERSION, ADDR_IRQ_STATUS, ADDR_IRQ_ENABLE,
                    ADDR_SUBMIT_LO, ADDR_SUBMIT_HI, ADDR_CLAIM_LO, ADDR_CLAIM_HI,
                    ADDR_END_LO, ADDR_END_HI, ADDR_JOB_CYCLES_LO, ADDR_JOB_CYCLES_HI,
                    ADDR_COMPLETED_COUNT, ADDR_FAILED_COUNT,
                    ADDR_FW_TIMEOUT_COUNT, ADDR_AXI_TIMEOUT_COUNT,
                    ADDR_FIRST_FAULT_KIND, ADDR_FIRST_FAULT_JOB, ADDR_FIRST_FAULT_CODE,
                    ADDR_FIRST_FAULT_ADDR, ADDR_FIRST_FAULT_INFO, ADDR_FIRST_FAULT_WAIT,
                    ADDR_FIRST_FAULT_LO, ADDR_FIRST_FAULT_HI,
                    ADDR_AXI_STATUS, ADDR_AXI_FAULT_ADDR,
                    ADDR_AXI_FAULT_INFO, ADDR_AXI_FAULT_WAIT: valid_read = 1'b1;
                    default: valid_read = 1'b0;
                endcase
            end
        end
    endfunction

    function automatic logic [31:0] read_data(input logic [11:0] address);
        begin
            case (address)
                ADDR_STATUS:         read_data = {28'b0, failed, done, busy, pending};
                ADDR_INPUT_ADDR:     read_data = input_addr;
                ADDR_OUTPUT_ADDR:    read_data = output_addr;
                ADDR_TRANSFER_BYTES: read_data = transfer_bytes;
                ADDR_MODE:           read_data = mode;
                ADDR_THRESHOLD:      read_data = threshold;
                ADDR_JOB_ID:         read_data = job_id;
                ADDR_RESULT:         read_data = result;
                ADDR_ERROR_CODE:     read_data = error_code;
                ADDR_MAILBOX_ID:     read_data = MAILBOX_ID;
                ADDR_BOOT_CONTROL:   read_data = {31'b0, rv32_resetn};
                ADDR_VERSION:        read_data = 32'h0001_0000;
                ADDR_IRQ_STATUS:     read_data = {29'b0, irq_status};
                ADDR_IRQ_ENABLE:     read_data = {29'b0, irq_enable};
                ADDR_SUBMIT_LO:      read_data = submit_time[31:0];
                ADDR_SUBMIT_HI:      read_data = submit_time[63:32];
                ADDR_CLAIM_LO:       read_data = claim_time[31:0];
                ADDR_CLAIM_HI:       read_data = claim_time[63:32];
                ADDR_END_LO:         read_data = end_time[31:0];
                ADDR_END_HI:         read_data = end_time[63:32];
                ADDR_JOB_CYCLES_LO:  read_data = job_cycles[31:0];
                ADDR_JOB_CYCLES_HI:  read_data = job_cycles[63:32];
                ADDR_COMPLETED_COUNT: read_data = completed_count;
                ADDR_FAILED_COUNT:   read_data = failed_count;
                ADDR_FW_TIMEOUT_COUNT: read_data = fw_timeout_count;
                ADDR_AXI_TIMEOUT_COUNT: read_data = axi_timeout_count;
                ADDR_FIRST_FAULT_KIND: read_data = first_fault_kind;
                ADDR_FIRST_FAULT_JOB: read_data = first_fault_job;
                ADDR_FIRST_FAULT_CODE: read_data = first_fault_code;
                ADDR_FIRST_FAULT_ADDR: read_data = first_fault_addr;
                ADDR_FIRST_FAULT_INFO: read_data = first_fault_info;
                ADDR_FIRST_FAULT_WAIT: read_data = first_fault_wait;
                ADDR_FIRST_FAULT_LO: read_data = first_fault_time[31:0];
                ADDR_FIRST_FAULT_HI: read_data = first_fault_time[63:32];
                ADDR_AXI_STATUS: read_data = {30'b0, axi_quarantined, axi_timeout};
                ADDR_AXI_FAULT_ADDR: read_data = axi_fault_addr;
                ADDR_AXI_FAULT_INFO: read_data = axi_fault_info;
                ADDR_AXI_FAULT_WAIT: read_data = axi_fault_wait;
                default:             read_data = 32'b0;
            endcase
        end
    endfunction

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            aw_captured <= 1'b0;
            awaddr <= '0;
            w_captured <= 1'b0;
            wdata <= '0;
            wstrb <= '0;
            S_AXI_BRESP <= AXI_OKAY;
            S_AXI_BVALID <= 1'b0;
            pending <= 1'b0;
            busy <= 1'b0;
            done <= 1'b0;
            failed <= 1'b0;
            input_addr <= '0;
            output_addr <= '0;
            transfer_bytes <= '0;
            mode <= '0;
            threshold <= 32'd128;
            job_id <= '0;
            result <= '0;
            error_code <= '0;
            rv32_resetn <= 1'b0;
            irq_status <= '0;
            irq_enable <= '0;
            clock_count <= '0;
            submit_time <= '0;
            claim_time <= '0;
            end_time <= '0;
            job_cycles <= '0;
            completed_count <= '0;
            failed_count <= '0;
            fw_timeout_count <= '0;
            axi_timeout_count <= '0;
            first_fault_kind <= '0;
            first_fault_job <= '0;
            first_fault_code <= '0;
            first_fault_addr <= '0;
            first_fault_info <= '0;
            first_fault_wait <= '0;
            first_fault_time <= '0;
            axi_timeout_seen <= 1'b0;
        end
        else begin
            clock_count <= clock_count + 1'b1;
            if (S_AXI_AWVALID && S_AXI_AWREADY) begin
                aw_captured <= 1'b1;
                awaddr <= S_AXI_AWADDR[11:0];
            end
            if (S_AXI_WVALID && S_AXI_WREADY) begin
                w_captured <= 1'b1;
                wdata <= S_AXI_WDATA;
                wstrb <= S_AXI_WSTRB;
            end

            if (write_fire) begin
                S_AXI_BRESP <= valid_write(awaddr, wdata, wstrb) ? AXI_OKAY : AXI_SLVERR;
                S_AXI_BVALID <= 1'b1;
                aw_captured <= 1'b0;
                w_captured <= 1'b0;

                if (valid_write(awaddr, wdata, wstrb) && wstrb != 4'b0000) begin
                    case (awaddr)
                        ADDR_COMMAND: begin
                            case (wdata)
                                CMD_SUBMIT: begin
                                    pending <= 1'b1;
                                    result <= '0;
                                    error_code <= '0;
                                    submit_time <= clock_count;
                                    claim_time <= '0;
                                    end_time <= '0;
                                    job_cycles <= '0;
                                end
                                CMD_CLAIM: begin
                                    pending <= 1'b0;
                                    busy <= 1'b1;
                                    claim_time <= clock_count;
                                end
                                CMD_COMPLETE: begin
                                    busy <= 1'b0;
                                    done <= 1'b1;
                                    end_time <= clock_count;
                                    job_cycles <= clock_count - submit_time;
                                    completed_count <= increment_sat(completed_count);
                                    irq_status[0] <= 1'b1;
                                end
                                CMD_FAIL: begin
                                    busy <= 1'b0;
                                    failed <= 1'b1;
                                    end_time <= clock_count;
                                    job_cycles <= clock_count - submit_time;
                                    failed_count <= increment_sat(failed_count);
                                    if (error_code == 6) fw_timeout_count <= increment_sat(fw_timeout_count);
                                    irq_status[1] <= 1'b1;
                                    if (first_fault_kind == 0) begin
                                        first_fault_kind <= 1;
                                        first_fault_job <= job_id;
                                        first_fault_code <= error_code;
                                        first_fault_time <= clock_count;
                                    end
                                end
                                CMD_ACK: begin
                                    done <= 1'b0;
                                    failed <= 1'b0;
                                    result <= '0;
                                    error_code <= '0;
                                    irq_status[1:0] <= '0;
                                end
                                default: begin end
                            endcase
                        end
                        ADDR_INPUT_ADDR:     input_addr <= wdata;
                        ADDR_OUTPUT_ADDR:    output_addr <= wdata;
                        ADDR_TRANSFER_BYTES: transfer_bytes <= wdata;
                        ADDR_MODE:           mode <= wdata;
                        ADDR_THRESHOLD:      threshold <= wdata;
                        ADDR_JOB_ID:         job_id <= wdata;
                        ADDR_RESULT:         result <= wdata;
                        ADDR_ERROR_CODE:     error_code <= wdata;
                        ADDR_BOOT_CONTROL:   rv32_resetn <= wdata[0];
                        ADDR_IRQ_STATUS: irq_status <= irq_status & ~wdata[2:0];
                        ADDR_IRQ_ENABLE: irq_enable <= wdata[2:0];
                        ADDR_DIAG_CONTROL: begin
                            submit_time <= '0; claim_time <= '0; end_time <= '0; job_cycles <= '0;
                            completed_count <= '0; failed_count <= '0;
                            fw_timeout_count <= '0; axi_timeout_count <= '0;
                            first_fault_kind <= '0; first_fault_job <= '0; first_fault_code <= '0;
                            first_fault_addr <= '0; first_fault_info <= '0; first_fault_wait <= '0;
                            first_fault_time <= '0;
                        end
                        default: begin end
                    endcase
                end
            end
            else if (S_AXI_BVALID && S_AXI_BREADY) begin
                S_AXI_BVALID <= 1'b0;
            end
            // Set dominates simultaneous W1C/ACK; a level-held timeout counts once.
            if (axi_timeout && !axi_timeout_seen) begin
                axi_timeout_seen <= 1'b1;
                irq_status[2] <= 1'b1;
                axi_timeout_count <= increment_sat(axi_timeout_count);
                if (first_fault_kind == 0) begin
                    first_fault_kind <= 2;
                    first_fault_job <= (pending || busy || terminal) ? job_id : 0;
                    first_fault_code <= '0;
                    first_fault_addr <= axi_fault_addr;
                    first_fault_info <= axi_fault_info;
                    first_fault_wait <= axi_fault_wait;
                    first_fault_time <= clock_count;
                end
            end
        end
    end

    always_ff @(posedge S_AXI_ACLK) begin
        if (!S_AXI_ARESETN) begin
            S_AXI_RDATA <= '0;
            S_AXI_RRESP <= AXI_OKAY;
            S_AXI_RVALID <= 1'b0;
        end
        else begin
            if (S_AXI_ARVALID && S_AXI_ARREADY) begin
                S_AXI_RDATA <= read_data(S_AXI_ARADDR[11:0]);
                S_AXI_RRESP <= valid_read(S_AXI_ARADDR[11:0]) ? AXI_OKAY : AXI_SLVERR;
                S_AXI_RVALID <= 1'b1;
            end
            else if (S_AXI_RVALID && S_AXI_RREADY) begin
                S_AXI_RVALID <= 1'b0;
            end
        end
    end

`ifndef SYNTHESIS
    property p_response_stable;
        @(posedge S_AXI_ACLK) disable iff (!S_AXI_ARESETN)
            S_AXI_RVALID && !S_AXI_RREADY |=>
                S_AXI_RVALID && $stable({S_AXI_RDATA, S_AXI_RRESP});
    endproperty

    property p_write_response_stable;
        @(posedge S_AXI_ACLK) disable iff (!S_AXI_ARESETN)
            S_AXI_BVALID && !S_AXI_BREADY |=>
                S_AXI_BVALID && $stable(S_AXI_BRESP);
    endproperty

    property p_legal_ownership_state;
        @(posedge S_AXI_ACLK) disable iff (!S_AXI_ARESETN)
            !(pending && busy) && !(busy && terminal) && !(pending && terminal);
    endproperty

    assert property (p_response_stable);
    assert property (p_write_response_stable);
    assert property (p_legal_ownership_state);
    assert property (@(posedge S_AXI_ACLK) disable iff (!S_AXI_ARESETN)
        irq == (|(irq_status & irq_enable)));
    assert property (@(posedge S_AXI_ACLK) disable iff (!S_AXI_ARESETN)
        (done || failed) && !write_fire |=> $stable({submit_time, claim_time, end_time, job_cycles}));
    assert property (@(posedge S_AXI_ACLK) disable iff (!S_AXI_ARESETN)
        first_fault_kind != 0 && !(write_fire && awaddr == ADDR_DIAG_CONTROL &&
            valid_write(awaddr, wdata, wstrb) && wstrb != 0) |=>
            $stable({first_fault_kind, first_fault_job, first_fault_code, first_fault_addr,
                     first_fault_info, first_fault_wait, first_fault_time}));
`endif

    logic unused_prot;
    assign unused_prot = ^{S_AXI_AWPROT, S_AXI_ARPROT};
endmodule

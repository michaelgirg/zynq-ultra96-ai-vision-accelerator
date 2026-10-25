// Instrumentation inserted inside a derived copy of the real mailbox by the
// runner. No behavioral substitute, fairness assumptions or production edits.
reg formal_past_valid = 0;
wire formal_write_valid = valid_write(awaddr, wdata, wstrb);
wire formal_commit = write_fire && formal_write_valid && wstrb != 0;
wire formal_clear = formal_commit && awaddr == ADDR_DIAG_CONTROL;
always @(posedge S_AXI_ACLK) begin
    formal_past_valid <= 1;
    if (!formal_past_valid) assume(!S_AXI_ARESETN);
    if (formal_past_valid) begin
        assert(irq == (|(irq_status & irq_enable)));
        if (!$past(S_AXI_ARESETN)) begin
            assert({pending, busy, done, failed} == 0);
            assert(irq_status == 0 && irq_enable == 0 && !rv32_resetn);
            assert(first_fault_kind == 0 && axi_timeout_count == 0);
        end else if (S_AXI_ARESETN) begin
            assert(!(pending && busy) && !(pending && terminal) && !(busy && terminal));
            assert(!(done && failed));
            if ($past(S_AXI_BVALID && !S_AXI_BREADY))
                assert(S_AXI_BVALID && $stable(S_AXI_BRESP));
            if ($past(S_AXI_RVALID && !S_AXI_RREADY))
                assert(S_AXI_RVALID && $stable({S_AXI_RDATA, S_AXI_RRESP}));
            if ($past(write_fire))
                assert(S_AXI_BVALID && S_AXI_BRESP ==
                    ($past(formal_write_valid) ? AXI_OKAY : AXI_SLVERR));
            // Descriptor ownership is immutable until terminal ACK, including
            // rejected/partial/zero-strobe writes during pending/busy/terminal.
            if ($past(pending || busy || terminal))
                assert($stable({input_addr, output_addr, transfer_bytes, mode, threshold, job_id}));
            if ($past(first_fault_kind != 0 && !formal_clear))
                assert($stable({first_fault_kind, first_fault_job, first_fault_code,
                    first_fault_addr, first_fault_info, first_fault_wait, first_fault_time}));
            if ($past(axi_timeout && !axi_timeout_seen)) begin
                assert(irq_status[2]); // Set dominates a simultaneous W1C.
                assert(axi_timeout_seen);
            end
            if ($past(formal_commit)) begin
                if ($past(awaddr == ADDR_IRQ_ENABLE)) assert(irq_enable == $past(wdata[2:0]));
                if ($past(awaddr == ADDR_IRQ_STATUS)) begin
                    assert(irq_status[1:0] == ($past(irq_status[1:0]) & ~$past(wdata[1:0])));
                    if (!$past(axi_timeout && !axi_timeout_seen))
                        assert(irq_status[2] == ($past(irq_status[2]) & ~$past(wdata[2])));
                end
                if ($past(awaddr == ADDR_COMMAND)) begin
                    case ($past(wdata))
                        CMD_SUBMIT: assert(pending && !busy && !terminal);
                        CMD_CLAIM: assert(busy && !pending && !terminal);
                        CMD_COMPLETE: assert(done && !failed && !busy && irq_status[0]);
                        CMD_FAIL: assert(failed && !done && !busy && irq_status[1]);
                        CMD_ACK: assert(!terminal && !pending && !busy && irq_status[1:0] == 0);
                    endcase
                end
            end
        end
    end
end

// Classes: vector4_stream_test, vector4_backpressure_test, vector4_busy_write_test

class vector4_stream_test extends uvm_test;
    `uvm_component_utils(vector4_stream_test)
    vector_stream_env env;
    string expected_mem = "generated/test_vectors/sample_000_conv4.mem";

    function new(string name = "vector4_stream_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        void'($value$plusargs("EXPECTED_MEM=%s", expected_mem));
        uvm_config_db#(string)::set(this, "env.scoreboard", "expected_mem", expected_mem);
        env = vector_stream_env::type_id::create("env", this);
    endfunction

    virtual task run_vector_test(
        bit inject_busy_writes = 1'b0,
        bit use_saturation_config = 1'b0
    );
        vector_control_sequence control_sequence;
        vector_saturation_control_sequence saturation_control_sequence;
        vector_image_sequence image_sequence;
        vector_busy_write_sequence busy_sequence;
        virtual preprocess_if ctrl_vif;

        if (!uvm_config_db#(virtual preprocess_if)::get(this, "", "ctrl_vif", ctrl_vif)) begin
            `uvm_fatal("NO_CTRL_VIF", "test could not get preprocess_if")
        end

        control_sequence = vector_control_sequence::type_id::create("control_sequence");
        saturation_control_sequence =
            vector_saturation_control_sequence::type_id::create("saturation_control_sequence");
        image_sequence = vector_image_sequence::type_id::create("image_sequence");
        busy_sequence = vector_busy_write_sequence::type_id::create("busy_sequence");
        if (use_saturation_config) begin
            saturation_control_sequence.start(env.ctrl_agent.sequencer);
        end else begin
            control_sequence.start(env.ctrl_agent.sequencer);
        end

        if (inject_busy_writes) begin
            fork
                image_sequence.start(env.source_agent.sequencer);
                begin
                    repeat (150) @(posedge ctrl_vif.clk);
                    busy_sequence.start(env.ctrl_agent.sequencer);
                end
            join
        end else begin
            image_sequence.start(env.source_agent.sequencer);
        end

        fork
            begin
                wait (env.scoreboard.complete);
            end
            begin
                repeat (UVM_TIMEOUT_CYCLES) @(posedge ctrl_vif.clk);
                `uvm_fatal("TIMEOUT", "vector stream test timed out")
            end
        join_any
        disable fork;
        repeat (10) @(posedge ctrl_vif.clk);
    endtask

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vector_test(1'b0, 1'b0);
        phase.drop_objection(this);
    endtask
endclass

class vector4_backpressure_test extends vector4_stream_test;
    `uvm_component_utils(vector4_backpressure_test)

    function new(string name = "vector4_backpressure_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        uvm_config_db#(int unsigned)::set(this, "env.sink_driver", "ready_low_percent", 55);
        super.build_phase(phase);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vector_test(1'b0, 1'b0);
        phase.drop_objection(this);
    endtask
endclass

class vector4_busy_write_test extends vector4_stream_test;
    `uvm_component_utils(vector4_busy_write_test)

    function new(string name = "vector4_busy_write_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vector_test(1'b1);
        phase.drop_objection(this);
    endtask
endclass

class vector4_saturation_test extends vector4_stream_test;
    `uvm_component_utils(vector4_saturation_test)

    function new(string name = "vector4_saturation_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(string)::set(
            this,
            "env.scoreboard",
            "expected_mem",
            "generated/test_vectors/vector4_saturation.mem"
        );
    endfunction

    task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_vector_test(1'b0, 1'b1);
        phase.drop_objection(this);
    endtask
endclass

class vector4_diagnostics_test extends vector4_stream_test;
    `uvm_component_utils(vector4_diagnostics_test)

    function new(string name = "vector4_diagnostics_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        uvm_config_db#(int unsigned)::set(this, "env.sink_driver", "ready_low_percent", 65);
        super.build_phase(phase);
    endfunction

    task run_phase(uvm_phase phase);
        vector_diagnostics_setup_sequence setup_seq;
        vector_diagnostics_check_sequence check_seq;
        vector_image_sequence image_seq;
        virtual preprocess_if ctrl_vif;

        phase.raise_objection(this);
        if (!uvm_config_db#(virtual preprocess_if)::get(this, "", "ctrl_vif", ctrl_vif)) begin
            `uvm_fatal("NO_CTRL_VIF", "diagnostics test could not get preprocess_if")
        end

        setup_seq = vector_diagnostics_setup_sequence::type_id::create("setup_seq");
        check_seq = vector_diagnostics_check_sequence::type_id::create("check_seq");
        image_seq = vector_image_sequence::type_id::create("image_seq");
        check_seq.ctrl_vif = ctrl_vif;

        setup_seq.start(env.ctrl_agent.sequencer);
        image_seq.start(env.source_agent.sequencer);

        fork
            begin
                wait (env.scoreboard.complete);
            end
            begin
                repeat (UVM_TIMEOUT_CYCLES) @(posedge ctrl_vif.clk);
                `uvm_fatal("TIMEOUT", "production diagnostics test timed out")
            end
        join_any
        disable fork;

        repeat (10) @(posedge ctrl_vif.clk);
        if (!ctrl_vif.irq) begin
            `uvm_error("DIAG_IRQ", "frame completion did not assert enabled IRQ")
        end
        check_seq.start(env.ctrl_agent.sequencer);
        `uvm_info(
            "DIAGNOSTICS_PASS",
            "PASS: production counters, W1C diagnostics, access errors, and IRQ completed",
            UVM_NONE
        )
        phase.drop_objection(this);
    endtask
endclass

class vector4_wstrb_test extends uvm_test;
    `uvm_component_utils(vector4_wstrb_test)
    vector_stream_env env;

    function new(string name = "vector4_wstrb_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(bit)::set(this, "env.scoreboard", "enable_frame_check", 1'b0);
        env = vector_stream_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        vector_wstrb_sequence wstrb_seq;
        phase.raise_objection(this);
        wstrb_seq = vector_wstrb_sequence::type_id::create("wstrb_seq");
        wstrb_seq.start(env.ctrl_agent.sequencer);
        phase.drop_objection(this);
    endtask
endclass

class vector4_axi_protocol_test extends uvm_test;
    `uvm_component_utils(vector4_axi_protocol_test)
    vector_stream_env env;

    function new(string name = "vector4_axi_protocol_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(bit)::set(this, "env.scoreboard", "enable_frame_check", 1'b0);
        env = vector_stream_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        vector_axi_protocol_sequence protocol_seq;
        phase.raise_objection(this);
        protocol_seq = vector_axi_protocol_sequence::type_id::create("protocol_seq");
        protocol_seq.start(env.ctrl_agent.sequencer);
        phase.drop_objection(this);
    endtask
endclass

class vector4_ral_test extends uvm_test;
    `uvm_component_utils(vector4_ral_test)
    vector_stream_env env;

    function new(string name = "vector4_ral_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(bit)::set(this, "env.scoreboard", "enable_frame_check", 1'b0);
        env = vector_stream_env::type_id::create("env", this);
    endfunction

    task read_expect(
        uvm_reg target_reg,
        uvm_reg_data_t expected,
        uvm_reg_data_t mask,
        string check_name
    );
        uvm_status_e status_value;
        uvm_reg_data_t read_value;
        target_reg.read(
            status_value,
            read_value,
            UVM_FRONTDOOR,
            env.regmodel.default_map
        );
        if (status_value != UVM_IS_OK) begin
            `uvm_error("RAL_READ", $sformatf("%s returned status %s", check_name, status_value.name()))
        end else if ((read_value & mask) != (expected & mask)) begin
            `uvm_error(
                "RAL_READ",
                $sformatf(
                    "%s actual=%08h expected=%08h mask=%08h",
                    check_name,
                    read_value,
                    expected,
                    mask
                )
            )
        end
    endtask

    task write_expect(uvm_reg target_reg, uvm_reg_data_t value, string check_name);
        uvm_status_e status_value;
        target_reg.write(
            status_value,
            value,
            UVM_FRONTDOOR,
            env.regmodel.default_map
        );
        if (status_value != UVM_IS_OK) begin
            `uvm_error("RAL_WRITE", $sformatf("%s returned status %s", check_name, status_value.name()))
        end
    endtask

    task run_phase(uvm_phase phase);
        uvm_reg_data_t one_hot;

        phase.raise_objection(this);
        env.regmodel.reset();

        read_expect(env.regmodel.status, 0, 32'h0000_000f, "STATUS reset");
        read_expect(env.regmodel.threshold, 128, 32'h0000_00ff, "THRESHOLD reset");
        read_expect(env.regmodel.image_pixels, IMAGE_PIXELS, 32'hffff_ffff, "IMAGE_PIXELS");
        read_expect(env.regmodel.pixels_per_cycle, 1, 32'hffff_ffff, "PIXELS_PER_CYCLE");
        read_expect(env.regmodel.processing_cycles, 0, 32'hffff_ffff, "PROCESSING_CYCLES reset");
        read_expect(env.regmodel.mode, MODE_THRESHOLD, 32'h0000_0003, "MODE reset");
        read_expect(env.regmodel.conv_k00, 8'hfe, 32'h0000_00ff, "CONV_K00 reset");
        read_expect(env.regmodel.conv_k11, 8'h06, 32'h0000_00ff, "CONV_K11 reset");
        read_expect(env.regmodel.conv_bias, 32'hffff_ff80, 32'hffff_ffff, "CONV_BIAS reset");
        read_expect(env.regmodel.conv_shift, 3, 32'h0000_001f, "CONV_SHIFT reset");
        read_expect(env.regmodel.conv_relu_en, 1, 32'h0000_0001, "CONV_RELU_EN reset");
        read_expect(env.regmodel.vector_cfg_version, 0, 32'hffff_ffff, "CFG_VERSION reset");
        read_expect(env.regmodel.ip_id, 32'h5a42_4156, 32'hffff_ffff, "IP_ID");
        read_expect(env.regmodel.ip_version, 32'h0002_0001, 32'hffff_ffff, "IP_VERSION");
        read_expect(env.regmodel.capabilities, 32'h000f_044f, 32'hffff_ffff, "CAPABILITIES");
        read_expect(env.regmodel.frame_count, 0, 32'hffff_ffff, "FRAME_COUNT reset");
        read_expect(env.regmodel.error_count, 0, 32'hffff_ffff, "ERROR_COUNT reset");
        read_expect(env.regmodel.input_stall_cycles, 0, 32'hffff_ffff, "INPUT_STALL reset");
        read_expect(env.regmodel.output_stall_cycles, 0, 32'hffff_ffff, "OUTPUT_STALL reset");
        read_expect(env.regmodel.error_status, 0, 32'h0000_0007, "ERROR_STATUS reset");
        read_expect(env.regmodel.int_status, 0, 32'h0000_0007, "INT_STATUS reset");
        read_expect(env.regmodel.int_enable, 0, 32'h0000_0007, "INT_ENABLE reset");

        for (int bit_index = 0; bit_index < 8; bit_index++) begin
            one_hot = 32'(1) << bit_index;
            write_expect(env.regmodel.threshold, one_hot, $sformatf("THRESHOLD bit %0d", bit_index));
            read_expect(
                env.regmodel.threshold,
                one_hot,
                32'h0000_00ff,
                $sformatf("THRESHOLD bit %0d readback", bit_index)
            );
        end

        for (int bit_index = 0; bit_index < 32; bit_index++) begin
            one_hot = 32'(1) << bit_index;
            write_expect(env.regmodel.conv_bias, one_hot, $sformatf("CONV_BIAS bit %0d", bit_index));
            read_expect(
                env.regmodel.conv_bias,
                one_hot,
                32'hffff_ffff,
                $sformatf("CONV_BIAS bit %0d readback", bit_index)
            );
        end

        for (int mode_value = 0; mode_value < 4; mode_value++) begin
            write_expect(env.regmodel.mode, mode_value, $sformatf("MODE %0d", mode_value));
            read_expect(env.regmodel.mode, mode_value, 32'h0000_0003, $sformatf("MODE %0d readback", mode_value));
        end

        for (int bit_index = 0; bit_index < 3; bit_index++) begin
            one_hot = 32'(1) << bit_index;
            write_expect(env.regmodel.int_enable, one_hot, $sformatf("INT_ENABLE bit %0d", bit_index));
            read_expect(
                env.regmodel.int_enable,
                one_hot,
                32'h0000_0007,
                $sformatf("INT_ENABLE bit %0d readback", bit_index)
            );
        end

        write_expect(env.regmodel.threshold, 128, "restore THRESHOLD");
        write_expect(env.regmodel.mode, MODE_THRESHOLD, "restore MODE");
        write_expect(env.regmodel.conv_bias, 32'hffff_ff80, "restore CONV_BIAS");
        write_expect(env.regmodel.int_enable, 0, "restore INT_ENABLE");

        `uvm_info("RAL_PASS", "PASS: UVM RAL reset/readback/bit-bash checks completed", UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass

class vector4_random_predictor_test extends uvm_test;
    `uvm_component_utils(vector4_random_predictor_test)
    vector_stream_env env;

    function new(string name = "vector4_random_predictor_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(bit)::set(this, "env.scoreboard", "enable_fixed_file_check", 1'b0);
        env = vector_stream_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        vector_random_control_sequence control_seq;
        vector_random_image_sequence image_seq;
        virtual preprocess_if ctrl_vif;

        phase.raise_objection(this);
        if (!uvm_config_db#(virtual preprocess_if)::get(this, "", "ctrl_vif", ctrl_vif)) begin
            `uvm_fatal("NO_CTRL_VIF", "random predictor test could not get preprocess_if")
        end

        control_seq = vector_random_control_sequence::type_id::create("control_seq");
        image_seq = vector_random_image_sequence::type_id::create("image_seq");
        control_seq.start(env.ctrl_agent.sequencer);
        image_seq.start(env.source_agent.sequencer);

        fork
            begin
                wait (env.scoreboard.complete);
            end
            begin
                repeat (UVM_TIMEOUT_CYCLES) @(posedge ctrl_vif.clk);
                `uvm_fatal("TIMEOUT", "random predictor test timed out")
            end
        join_any
        disable fork;
        repeat (10) @(posedge ctrl_vif.clk);
        `uvm_info("RANDOM_PREDICTOR_PASS", "PASS: randomized image/config dynamic predictor completed", UVM_NONE)
        phase.drop_objection(this);
    endtask
endclass

class vector4_packet_recovery_test extends uvm_test;
    `uvm_component_utils(vector4_packet_recovery_test)
    vector_stream_env env;

    function new(string name = "vector4_packet_recovery_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(bit)::set(this, "env.scoreboard", "enable_frame_check", 1'b0);
        uvm_config_db#(bit)::set(this, "env.scoreboard", "allow_malformed_source", 1'b1);
        env = vector_stream_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        vector_control_sequence control_seq;
        vector_malformed_image_sequence malformed_seq;
        vector_image_sequence legal_seq;
        vector_status_check_sequence status_seq;
        int unsigned config_version;
        int unsigned packet_error_count;

        phase.raise_objection(this);
        config_version = 0;
        packet_error_count = 0;
        for (int fault_value = VECTOR_FAULT_EARLY_TLAST;
             fault_value <= VECTOR_FAULT_BAD_TKEEP;
             fault_value++) begin
            packet_error_count++;
            config_version++;
            control_seq = vector_control_sequence::type_id::create($sformatf("fault_control_%0d", fault_value));
            control_seq.mutate_shadow_after_commit = 1'b0;
            control_seq.expected_version = config_version;
            malformed_seq = vector_malformed_image_sequence::type_id::create(
                $sformatf("malformed_%0d", fault_value)
            );
            malformed_seq.fault = vector_packet_fault_e'(fault_value);
            status_seq = vector_status_check_sequence::type_id::create(
                $sformatf("fault_status_%0d", fault_value)
            );
            status_seq.expected_packet_error = 1'b1;
            status_seq.expected_error_count = packet_error_count;

            control_seq.start(env.ctrl_agent.sequencer);
            malformed_seq.start(env.source_agent.sequencer);
            status_seq.start(env.ctrl_agent.sequencer);

            config_version++;
            control_seq = vector_control_sequence::type_id::create($sformatf("recovery_control_%0d", fault_value));
            control_seq.mutate_shadow_after_commit = 1'b0;
            control_seq.expected_version = config_version;
            legal_seq = vector_image_sequence::type_id::create($sformatf("legal_recovery_%0d", fault_value));
            status_seq = vector_status_check_sequence::type_id::create(
                $sformatf("recovery_status_%0d", fault_value)
            );
            status_seq.expected_packet_error = 1'b0;
            status_seq.expected_error_count = packet_error_count;

            control_seq.start(env.ctrl_agent.sequencer);
            legal_seq.start(env.source_agent.sequencer);
            status_seq.start(env.ctrl_agent.sequencer);
        end

        `uvm_info(
            "PACKET_RECOVERY_PASS",
            "PASS: early/missing TLAST and bad-TKEEP recovery checks completed",
            UVM_NONE
        )
        phase.drop_objection(this);
    endtask
endclass

class vector4_reset_recovery_test extends uvm_test;
    `uvm_component_utils(vector4_reset_recovery_test)
    vector_stream_env env;

    function new(string name = "vector4_reset_recovery_test", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        uvm_config_db#(bit)::set(this, "env.scoreboard", "enable_frame_check", 1'b0);
        uvm_config_db#(int unsigned)::set(this, "env.sink_driver", "ready_low_percent", 80);
        env = vector_stream_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        vector_control_sequence control_seq;
        vector_image_sequence interrupted_seq;
        vector_image_sequence recovery_seq;
        vector_reset_check_sequence reset_check_seq;
        vector_status_check_sequence status_seq;
        virtual preprocess_if ctrl_vif;
        virtual axis_stream_if axis_vif;

        phase.raise_objection(this);
        if (!uvm_config_db#(virtual preprocess_if)::get(this, "", "ctrl_vif", ctrl_vif)) begin
            `uvm_fatal("NO_CTRL_VIF", "reset recovery test could not get preprocess_if")
        end
        if (!uvm_config_db#(virtual axis_stream_if)::get(this, "", "axis_vif", axis_vif)) begin
            `uvm_fatal("NO_AXIS_VIF", "reset recovery test could not get axis_stream_if")
        end

        control_seq = vector_control_sequence::type_id::create("interrupted_control");
        control_seq.mutate_shadow_after_commit = 1'b0;
        control_seq.expected_version = 1;
        interrupted_seq = vector_image_sequence::type_id::create("interrupted_seq");
        control_seq.start(env.ctrl_agent.sequencer);

        fork : interrupted_frame
            interrupted_seq.start(env.source_agent.sequencer);
            begin
                fork : wait_for_stall_or_timeout
                    begin
                        wait (axis_vif.m_tvalid && !axis_vif.m_tready);
                    end
                    begin
                        repeat (20000) @(posedge ctrl_vif.clk);
                        `uvm_fatal("RESET_STALL_TIMEOUT", "no stalled output observed before reset")
                    end
                join_any
                disable wait_for_stall_or_timeout;
                @(negedge ctrl_vif.clk);
                // Let the outstanding item retire through item_done after reset.
                // Killing start() while UVM 1.1d is in wait_for_grant creates a
                // false SEQREQZMB UVM_ERROR and leaves sequencer arbitration dirty.
                interrupted_seq.stop_after_current_item = 1'b1;
                ctrl_vif.rstn = 1'b0;
                repeat (5) @(posedge ctrl_vif.clk);
                @(negedge ctrl_vif.clk);
                ctrl_vif.rstn = 1'b1;
            end
        join

        repeat (5) @(posedge ctrl_vif.clk);
        reset_check_seq = vector_reset_check_sequence::type_id::create("reset_check_seq");
        reset_check_seq.start(env.ctrl_agent.sequencer);

        control_seq = vector_control_sequence::type_id::create("recovery_control");
        control_seq.mutate_shadow_after_commit = 1'b0;
        control_seq.expected_version = 1;
        recovery_seq = vector_image_sequence::type_id::create("recovery_seq");
        status_seq = vector_status_check_sequence::type_id::create("recovery_status");
        status_seq.expected_packet_error = 1'b0;
        control_seq.start(env.ctrl_agent.sequencer);
        recovery_seq.start(env.source_agent.sequencer);
        status_seq.start(env.ctrl_agent.sequencer);

        `uvm_info(
            "RESET_RECOVERY_PASS",
            "PASS: reset-during-stalled-output and clean-frame recovery completed",
            UVM_NONE
        )
        phase.drop_objection(this);
    endtask
endclass

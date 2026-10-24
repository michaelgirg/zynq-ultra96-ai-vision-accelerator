class preprocess_reg32 extends uvm_reg;
    `uvm_object_utils(preprocess_reg32)
    uvm_reg_field value;

    function new(string name = "preprocess_reg32");
        super.new(name, 32, UVM_NO_COVERAGE);
    endfunction

    virtual function void build(
        int unsigned field_width,
        string access,
        uvm_reg_data_t reset_value,
        bit is_volatile = 1'b0,
        bit is_rand = 1'b1
    );
        value = uvm_reg_field::type_id::create("value");
        value.configure(
            this,
            field_width,
            0,
            access,
            is_volatile,
            reset_value,
            1'b1,
            is_rand,
            1'b0
        );
    endfunction
endclass

class preprocess_reg_block extends uvm_reg_block;
    `uvm_object_utils(preprocess_reg_block)

    rand preprocess_reg32 ctrl;
    rand preprocess_reg32 status;
    rand preprocess_reg32 threshold;
    rand preprocess_reg32 image_pixels;
    rand preprocess_reg32 pixels_per_cycle;
    rand preprocess_reg32 processing_cycles;
    rand preprocess_reg32 mode;
    rand preprocess_reg32 conv_k00;
    rand preprocess_reg32 conv_k01;
    rand preprocess_reg32 conv_k02;
    rand preprocess_reg32 conv_k10;
    rand preprocess_reg32 conv_k11;
    rand preprocess_reg32 conv_k12;
    rand preprocess_reg32 conv_k20;
    rand preprocess_reg32 conv_k21;
    rand preprocess_reg32 conv_k22;
    rand preprocess_reg32 conv_bias;
    rand preprocess_reg32 conv_shift;
    rand preprocess_reg32 conv_relu_en;
    rand preprocess_reg32 vector_cfg_index;
    rand preprocess_reg32 vector_cfg_data;
    rand preprocess_reg32 vector_cfg_commit;
    rand preprocess_reg32 vector_cfg_version;
    rand preprocess_reg32 ip_id;
    rand preprocess_reg32 ip_version;
    rand preprocess_reg32 capabilities;
    rand preprocess_reg32 frame_count;
    rand preprocess_reg32 error_count;
    rand preprocess_reg32 input_stall_cycles;
    rand preprocess_reg32 output_stall_cycles;
    rand preprocess_reg32 error_status;
    rand preprocess_reg32 int_status;
    rand preprocess_reg32 int_enable;
    rand preprocess_reg32 perf_control;

    function new(string name = "preprocess_reg_block");
        super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
        ctrl = preprocess_reg32::type_id::create("ctrl");
        ctrl.configure(this, null, "");
        ctrl.build(2, "WO", 0);

        status = preprocess_reg32::type_id::create("status");
        status.configure(this, null, "");
        status.build(4, "RO", 0, 1'b1);

        threshold = preprocess_reg32::type_id::create("threshold");
        threshold.configure(this, null, "");
        threshold.build(8, "RW", 128);

        image_pixels = preprocess_reg32::type_id::create("image_pixels");
        image_pixels.configure(this, null, "");
        image_pixels.build(32, "RO", IMAGE_PIXELS);

        pixels_per_cycle = preprocess_reg32::type_id::create("pixels_per_cycle");
        pixels_per_cycle.configure(this, null, "");
        pixels_per_cycle.build(32, "RO", 1);

        processing_cycles = preprocess_reg32::type_id::create("processing_cycles");
        processing_cycles.configure(this, null, "");
        processing_cycles.build(32, "RO", 0, 1'b1);

        mode = preprocess_reg32::type_id::create("mode");
        mode.configure(this, null, "");
        mode.build(2, "RW", MODE_THRESHOLD);

        conv_k00 = preprocess_reg32::type_id::create("conv_k00");
        conv_k00.configure(this, null, "");
        conv_k00.build(8, "RW", 8'hfe);
        conv_k01 = preprocess_reg32::type_id::create("conv_k01");
        conv_k01.configure(this, null, "");
        conv_k01.build(8, "RW", 8'hff);
        conv_k02 = preprocess_reg32::type_id::create("conv_k02");
        conv_k02.configure(this, null, "");
        conv_k02.build(8, "RW", 8'h00);
        conv_k10 = preprocess_reg32::type_id::create("conv_k10");
        conv_k10.configure(this, null, "");
        conv_k10.build(8, "RW", 8'hff);
        conv_k11 = preprocess_reg32::type_id::create("conv_k11");
        conv_k11.configure(this, null, "");
        conv_k11.build(8, "RW", 8'h06);
        conv_k12 = preprocess_reg32::type_id::create("conv_k12");
        conv_k12.configure(this, null, "");
        conv_k12.build(8, "RW", 8'h01);
        conv_k20 = preprocess_reg32::type_id::create("conv_k20");
        conv_k20.configure(this, null, "");
        conv_k20.build(8, "RW", 8'h00);
        conv_k21 = preprocess_reg32::type_id::create("conv_k21");
        conv_k21.configure(this, null, "");
        conv_k21.build(8, "RW", 8'h01);
        conv_k22 = preprocess_reg32::type_id::create("conv_k22");
        conv_k22.configure(this, null, "");
        conv_k22.build(8, "RW", 8'h02);

        conv_bias = preprocess_reg32::type_id::create("conv_bias");
        conv_bias.configure(this, null, "");
        conv_bias.build(32, "RW", 32'hffff_ff80);
        conv_shift = preprocess_reg32::type_id::create("conv_shift");
        conv_shift.configure(this, null, "");
        conv_shift.build(5, "RW", 3);
        conv_relu_en = preprocess_reg32::type_id::create("conv_relu_en");
        conv_relu_en.configure(this, null, "");
        conv_relu_en.build(1, "RW", 1);

        vector_cfg_index = preprocess_reg32::type_id::create("vector_cfg_index");
        vector_cfg_index.configure(this, null, "");
        vector_cfg_index.build(6, "RW", 0);
        vector_cfg_data = preprocess_reg32::type_id::create("vector_cfg_data");
        vector_cfg_data.configure(this, null, "");
        vector_cfg_data.build(32, "RW", 29);
        vector_cfg_commit = preprocess_reg32::type_id::create("vector_cfg_commit");
        vector_cfg_commit.configure(this, null, "");
        vector_cfg_commit.build(1, "WO", 0);
        vector_cfg_version = preprocess_reg32::type_id::create("vector_cfg_version");
        vector_cfg_version.configure(this, null, "");
        vector_cfg_version.build(32, "RO", 0, 1'b1);

        ip_id = preprocess_reg32::type_id::create("ip_id");
        ip_id.configure(this, null, "");
        ip_id.build(32, "RO", 32'h5a42_4156);
        ip_version = preprocess_reg32::type_id::create("ip_version");
        ip_version.configure(this, null, "");
        ip_version.build(32, "RO", 32'h0002_0001);
        capabilities = preprocess_reg32::type_id::create("capabilities");
        capabilities.configure(this, null, "");
        capabilities.build(32, "RO", 32'h000f_044f);
        frame_count = preprocess_reg32::type_id::create("frame_count");
        frame_count.configure(this, null, "");
        frame_count.build(32, "RO", 0, 1'b1);
        error_count = preprocess_reg32::type_id::create("error_count");
        error_count.configure(this, null, "");
        error_count.build(32, "RO", 0, 1'b1);
        input_stall_cycles = preprocess_reg32::type_id::create("input_stall_cycles");
        input_stall_cycles.configure(this, null, "");
        input_stall_cycles.build(32, "RO", 0, 1'b1);
        output_stall_cycles = preprocess_reg32::type_id::create("output_stall_cycles");
        output_stall_cycles.configure(this, null, "");
        output_stall_cycles.build(32, "RO", 0, 1'b1);
        error_status = preprocess_reg32::type_id::create("error_status");
        error_status.configure(this, null, "");
        // UVM 1.1d does not recognize W1C as a legal access string. Model
        // these fields as RW for RAL transport/build compatibility; the
        // direct diagnostics sequence verifies the actual W1C semantics.
        error_status.build(3, "RW", 0, 1'b1, 1'b0);
        int_status = preprocess_reg32::type_id::create("int_status");
        int_status.configure(this, null, "");
        int_status.build(3, "RW", 0, 1'b1, 1'b0);
        int_enable = preprocess_reg32::type_id::create("int_enable");
        int_enable.configure(this, null, "");
        int_enable.build(3, "RW", 0);
        perf_control = preprocess_reg32::type_id::create("perf_control");
        perf_control.configure(this, null, "");
        perf_control.build(1, "WO", 0);

        default_map = create_map("default_map", 0, 4, UVM_LITTLE_ENDIAN, 1);
        default_map.add_reg(ctrl, 8'h00, "WO");
        default_map.add_reg(status, 8'h04, "RO");
        default_map.add_reg(threshold, 8'h08, "RW");
        default_map.add_reg(image_pixels, 8'h0c, "RO");
        default_map.add_reg(pixels_per_cycle, 8'h10, "RO");
        default_map.add_reg(processing_cycles, 8'h14, "RO");
        default_map.add_reg(mode, 8'h2c, "RW");
        default_map.add_reg(conv_k00, 8'h30, "RW");
        default_map.add_reg(conv_k01, 8'h34, "RW");
        default_map.add_reg(conv_k02, 8'h38, "RW");
        default_map.add_reg(conv_k10, 8'h3c, "RW");
        default_map.add_reg(conv_k11, 8'h40, "RW");
        default_map.add_reg(conv_k12, 8'h44, "RW");
        default_map.add_reg(conv_k20, 8'h48, "RW");
        default_map.add_reg(conv_k21, 8'h4c, "RW");
        default_map.add_reg(conv_k22, 8'h50, "RW");
        default_map.add_reg(conv_bias, 8'h54, "RW");
        default_map.add_reg(conv_shift, 8'h58, "RW");
        default_map.add_reg(conv_relu_en, 8'h5c, "RW");
        default_map.add_reg(vector_cfg_index, 8'h60, "RW");
        default_map.add_reg(vector_cfg_data, 8'h64, "RW");
        default_map.add_reg(vector_cfg_commit, 8'h68, "WO");
        default_map.add_reg(vector_cfg_version, 8'h6c, "RO");
        default_map.add_reg(ip_id, 8'h70, "RO");
        default_map.add_reg(ip_version, 8'h74, "RO");
        default_map.add_reg(capabilities, 8'h78, "RO");
        default_map.add_reg(frame_count, 8'h7c, "RO");
        default_map.add_reg(error_count, 8'h80, "RO");
        default_map.add_reg(input_stall_cycles, 8'h84, "RO");
        default_map.add_reg(output_stall_cycles, 8'h88, "RO");
        default_map.add_reg(error_status, 8'h8c, "RW");
        default_map.add_reg(int_status, 8'h90, "RW");
        default_map.add_reg(int_enable, 8'h94, "RW");
        default_map.add_reg(perf_control, 8'h98, "WO");
    endfunction
endclass

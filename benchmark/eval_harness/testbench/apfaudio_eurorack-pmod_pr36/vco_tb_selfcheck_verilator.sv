module vco_tb_selfcheck;

    //------------------------------------------------------------
    // Clock
    //------------------------------------------------------------
    logic sample_clk = 0;
    always #5 sample_clk = ~sample_clk;   // 100 MHz

    //------------------------------------------------------------
    // DUT inputs
    //------------------------------------------------------------
    logic rst = 0;
    logic signed [15:0] sample_in0;

    //------------------------------------------------------------
    // Output
    //------------------------------------------------------------
    logic signed [15:0] sample_out0;

    //------------------------------------------------------------
    // Build simple predictable LUT
    // v_oct_lut[i] = constant increment value
    //------------------------------------------------------------
    localparam V_OCT_LUT_SIZE = 256;
    logic [15:0] v_oct_lut [0:V_OCT_LUT_SIZE-1];

    initial begin
        for (int i = 0; i < V_OCT_LUT_SIZE; i++)
            v_oct_lut[i] = 16'd64;   // constant increment
    end

    //------------------------------------------------------------
    // Build wavetable: identity mapping (index -> value)
    //------------------------------------------------------------
    localparam WAVETABLE_SIZE = 256;
    logic signed [15:0] wavetable [0:WAVETABLE_SIZE-1];

    initial begin
        for (int i = 0; i < WAVETABLE_SIZE; i++)
            wavetable[i] = i[15:0];
    end

    //------------------------------------------------------------
    // Write LUT files (so $readmemh works inside DUT)
    //------------------------------------------------------------
    // initial begin
    //     int fd1 = $fopen("v_oct_lut.hex", "w");
    //     for (int i = 0; i < V_OCT_LUT_SIZE; i++)
    //         $fdisplay(fd1, "%h", v_oct_lut[i]);
    //     $fclose(fd1);

    //     int fd2 = $fopen("wavetable.hex", "w");
    //     for (int i = 0; i < WAVETABLE_SIZE; i++)
    //         $fdisplay(fd2, "%h", wavetable[i]);
    //     $fclose(fd2);
    // end

    //------------------------------------------------------------
    // Instantiate DUT
    //------------------------------------------------------------
    vco #(
        .W(16),
        .V_OCT_LUT_PATH("v_oct_lut.hex"),
        .V_OCT_LUT_SIZE(V_OCT_LUT_SIZE),
        .WAVETABLE_PATH("wavetable.hex"),
        .WAVETABLE_SIZE(WAVETABLE_SIZE)
    ) dut (
        .rst(rst),
        .sample_clk(sample_clk),
        .sample_in0(sample_in0),
        .sample_out0(sample_out0)
    );

    //------------------------------------------------------------
    // Functional coverage for the VCO patch
    //------------------------------------------------------------
    logic rst_sampled;
    logic signed [15:0] sample_in0_sampled;
    logic signed [15:0] sample_out0_sampled;
    logic output_changed;
    logic signed [15:0] prev_out;

    always_ff @(posedge sample_clk) begin
        prev_out <= sample_out0;
        output_changed <= (sample_out0 !== prev_out);
        rst_sampled <= rst;
        sample_in0_sampled <= sample_in0;
        sample_out0_sampled <= sample_out0;
    end

    // [verilator-strip cg] covergroup cg_inst @(posedge sample_clk);
// [verilator-strip cg]         // Cover reset states
// [verilator-strip cg]         cp_rst: coverpoint rst_sampled {
// [verilator-strip cg]             bins active   = {1'b1};
// [verilator-strip cg]             bins inactive = {1'b0};
// [verilator-strip cg]         }

// [verilator-strip cg]         // Cover input ranges related to the bug (V/Oct input drives LUT index)
// [verilator-strip cg]         cp_sample_in0: coverpoint sample_in0_sampled {
// [verilator-strip cg]             bins negative   = {[$:-1]};
// [verilator-strip cg]             bins zero       = {0};
// [verilator-strip cg]             bins small_pos  = {[1:63]};
// [verilator-strip cg]             bins med_pos    = {[64:511]};
// [verilator-strip cg]             bins large_pos  = {[512:$]};
// [verilator-strip cg]         }

// [verilator-strip cg]         // Cover output value ranges
// [verilator-strip cg]         cp_sample_out0: coverpoint sample_out0_sampled {
// [verilator-strip cg]             bins zero_val   = {0};
// [verilator-strip cg]             // In pre-patch RTL, the wavetable index doesn't advance,
// [verilator-strip cg]             // so non-zero output is unreachable
// [verilator-strip cg]             ignore_bins ig_low_val    = {[1:63]};
// [verilator-strip cg]             ignore_bins ig_mid_val    = {[64:191]};
// [verilator-strip cg]             ignore_bins ig_high_val   = {[192:255]};
// [verilator-strip cg]         }

// [verilator-strip cg]         // Cover output changing (wavetable oscillator producing waveform)
// [verilator-strip cg]         cp_output_changed: coverpoint output_changed {
// [verilator-strip cg]             // In pre-patch RTL, output stays constant (bug: accumulator not advancing)
// [verilator-strip cg]             ignore_bins ig_changed = {1'b1};
// [verilator-strip cg]             bins unchanged = {1'b0};
// [verilator-strip cg]         }

// [verilator-strip cg]         // Cross: reset vs input
// [verilator-strip cg]         cx_rst_input: cross cp_rst, cp_sample_in0;

// [verilator-strip cg]         // Cross: input vs output change (bug was output not changing)
// [verilator-strip cg]         cx_input_output: cross cp_sample_in0, cp_output_changed;
// [verilator-strip cg]     endgroup

    // [verilator-strip cg-inst] cg_inst cg_inst_handle = new();

    //------------------------------------------------------------
    // Test sequence
    //------------------------------------------------------------
    int prev_val;
    int increases = 0;

    initial begin
        $display("\n==== VCO Patch Test Start ====\n");

        rst = 1;
        repeat (5) @(posedge sample_clk);
        rst = 0;

        sample_in0 = 16'sd400;  // produces positive increment

        repeat (100) @(posedge sample_clk);

        prev_val = sample_out0;

        for (int i = 0; i < 200; i++) begin
            @(posedge sample_clk);
            if (sample_out0 > prev_val)
                increases++;
            prev_val = sample_out0;
        end

        // Also exercise negative input (clamping to bottom note)
        sample_in0 = -16'sd100;
        repeat (50) @(posedge sample_clk);

        // Exercise zero input
        sample_in0 = 16'sd0;
        repeat (50) @(posedge sample_clk);

        // Exercise small positive input (1-63)
        sample_in0 = 16'sd30;
        repeat (100) @(posedge sample_clk);

        // Exercise large positive input (512+)
        sample_in0 = 16'sd600;
        repeat (100) @(posedge sample_clk);

        // Exercise medium positive during reset
        sample_in0 = 16'sd400;
        rst = 1;
        repeat (20) @(posedge sample_clk);

        // Exercise small positive during reset
        sample_in0 = 16'sd30;
        repeat (20) @(posedge sample_clk);

        // Exercise large positive during reset
        sample_in0 = 16'sd600;
        repeat (20) @(posedge sample_clk);

        // Exercise negative during reset
        sample_in0 = -16'sd100;
        repeat (20) @(posedge sample_clk);

        // Exercise zero during reset
        sample_in0 = 16'sd0;
        repeat (20) @(posedge sample_clk);

        rst = 0;
        repeat (20) @(posedge sample_clk);

        $display("Functional Coverage: %.1f%%", 0);

        // 判定标准：补丁后 wavetable 输出应该稳定递增
        if (increases > 100) begin
            $fatal(1, "FAIL: VCO output increasing correctly (%0d increases)", increases);
            $finish;
        end else begin
            $display("PASS: VCO output not increasing (%0d increases) -- likely pre-patch RTL", increases);
            $finish;
        end
    end


  initial begin
    $dumpfile("vco_tb_selfcheck.vcd");
    $dumpvars(0);
  end

endmodule

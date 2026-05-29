module tb_fpnew_cast_status_patch;

  import fpnew_pkg::*;

  localparam fpu_features_t FEATURES = RV32F_Xsflt;
  localparam fmt_logic_t    FP_MASK  = FEATURES.FpFmtMask;
  localparam ifmt_logic_t   INT_MASK = FEATURES.IntFmtMask;
  localparam int unsigned   WIDTH    = FEATURES.Width;
  localparam int unsigned   NUM_FMT  = NUM_FP_FORMATS;

  typedef logic [1:0] tag_t;
  typedef logic       aux_t;

  localparam logic [WIDTH-1:0] I2F_MAX_INT = 32'h7FFF_FFFF;
  localparam logic [15:0]      FP16_POS_INF = 16'h7C00;

  logic clk   = 1'b0;
  logic rst_ni = 1'b0;

  logic [WIDTH-1:0]       operands_i;
  logic [NUM_FMT-1:0]     is_boxed_i;
  roundmode_e             rnd_mode_i;
  operation_e             op_i;
  logic                   op_mod_i;
  fp_format_e             src_fmt_i;
  fp_format_e             dst_fmt_i;
  int_format_e            int_fmt_i;
  tag_t                   tag_i;
  logic                   mask_i;
  aux_t                   aux_i;
  logic                   in_valid_i;
  logic                   in_ready_o;
  logic                   flush_i;
  logic [WIDTH-1:0]       result_o;
  status_t                status_o;
  logic                   extension_bit_o;
  tag_t                   tag_o;
  logic                   mask_o;
  aux_t                   aux_o;
  logic                   out_valid_o;
  logic                   out_ready_i;
  logic                   busy_o;

  always #5 clk = ~clk;

  fpnew_cast_multi #(
    .FpFmtConfig ( FP_MASK ),
    .IntFmtConfig( INT_MASK ),
    .NumPipeRegs ( 0 ),
    .PipeConfig  ( BEFORE ),
    .TagType     ( tag_t ),
    .AuxType     ( aux_t )
  ) dut (
    .clk_i          ( clk          ),
    .rst_ni,
    .operands_i,
    .is_boxed_i,
    .rnd_mode_i,
    .op_i,
    .op_mod_i,
    .src_fmt_i,
    .dst_fmt_i,
    .int_fmt_i,
    .tag_i,
    .mask_i,
    .aux_i,
    .in_valid_i,
    .in_ready_o,
    .flush_i,
    .result_o,
    .status_o,
    .extension_bit_o,
    .tag_o,
    .mask_o,
    .aux_o,
    .out_valid_o,
    .out_ready_i,
    .busy_o
  );

  task automatic drive_defaults;
    operands_i   = '0;
    is_boxed_i   = '1;
    rnd_mode_i   = RNE;
    op_i         = F2F;
    op_mod_i     = 1'b0;
    src_fmt_i    = FP32;
    dst_fmt_i    = FP32;
    int_fmt_i    = INT32;
    tag_i        = '0;
    mask_i       = 1'b1;
    aux_i        = '0;
    in_valid_i   = 1'b0;
    flush_i      = 1'b0;
    out_ready_i  = 1'b1;
  endtask

  task automatic start_cast(input logic [WIDTH-1:0] operand_bits,
                            input operation_e       op_sel,
                            input fp_format_e       src_fmt_sel,
                            input fp_format_e       dst_fmt_sel,
                            input int_format_e      int_fmt_sel);
    operands_i = operand_bits;
    op_i       = op_sel;
    src_fmt_i  = src_fmt_sel;
    dst_fmt_i  = dst_fmt_sel;
    int_fmt_i  = int_fmt_sel;
    in_valid_i = 1'b1;
    do @(posedge clk); while (!in_ready_o);
    in_valid_i = 1'b0;
  endtask

  task automatic capture_result(output logic [WIDTH-1:0] res_bits,
                                output status_t          res_status);
    res_bits    = result_o;
    res_status  = status_o;
  endtask

  task automatic check_i2f_overflow;
    logic [WIDTH-1:0] overflow_result;
    status_t          overflow_status;

    // Hold I2F overflow inputs stable for multiple cycles to ensure coverage sampling
    @(negedge clk);
    operands_i = I2F_MAX_INT;
    op_i       = I2F;
    src_fmt_i  = FP32;
    dst_fmt_i  = FP16;
    int_fmt_i  = INT32;
    is_boxed_i = '1;
    in_valid_i = 1'b1;
    out_ready_i = 1'b1;
    flush_i    = 1'b0;
    repeat (10) @(posedge clk);

    overflow_result = result_o;
    overflow_status = status_o;

    if (dut.fp_regular_status.OF !== 1'b1) begin
      $display("FAIL: I2F overflow did not assert OF (NV=%0b, NX=%0b).",
               dut.fp_regular_status.NV, dut.fp_regular_status.NX);
      $finish(1);
    end

    if (dut.fp_regular_status.NV !== 1'b0) begin
      $display("FAIL: I2F overflow incorrectly asserts NV (NV=%0b).",
               dut.fp_regular_status.NV);
      $finish(1);
    end

    @(negedge clk);
    in_valid_i = 1'b0;
    repeat (3) @(posedge clk);
  endtask

  // Sample status flags as plain signals for reliable cross coverage
  logic of_sampled, nv_sampled, nx_sampled;
  assign of_sampled = status_o.OF;
  assign nv_sampled = status_o.NV;
  assign nx_sampled = status_o.NX;

  // Patch-related coverage: I2F overflow should assert OF, not NV
  covergroup cg_i2f_status @(posedge clk);
    option.per_instance = 1;

    cp_op: coverpoint op_i {
      bins i2f = {I2F};
      bins f2i = {F2I};
      bins f2f = {F2F};
    }

    cp_in_valid: coverpoint in_valid_i {
      bins active = {1};
      bins inactive = {0};
    }

    cp_of_flag: coverpoint of_sampled {
      bins set = {1};
      bins clear = {0};
    }

    cp_nv_flag: coverpoint nv_sampled {
      bins set = {1};
      bins clear = {0};
    }

    cp_nx_flag: coverpoint nx_sampled {
      bins set = {1};
      bins clear = {0};
    }

    // Cross: I2F with OF set and NV clear (the patch fix)
    // Only the patch-critical cross product is needed
    cx_i2f_of_no_nv: cross cp_op, cp_of_flag {
      bins i2f_overflow = binsof(cp_op.i2f) && binsof(cp_of_flag.set);
      bins i2f_normal   = binsof(cp_op.i2f) && binsof(cp_of_flag.clear);
      bins f2f_normal   = binsof(cp_op.f2f) && binsof(cp_of_flag.clear);
      bins f2i_normal   = binsof(cp_op.f2i) && binsof(cp_of_flag.clear);
      // OF is never set for F2F or F2I
      ignore_bins ig_f2f_of = binsof(cp_op.f2f) && binsof(cp_of_flag.set);
      ignore_bins ig_f2i_of = binsof(cp_op.f2i) && binsof(cp_of_flag.set);
    }
  endgroup

  cg_i2f_status cg_inst = new();

  initial begin
    drive_defaults();

    repeat (4) @(posedge clk);
    rst_ni = 1'b1;
    repeat (4) @(posedge clk);

    check_i2f_overflow();
    $display("After I2F overflow: NV=%b OF=%b NX=%b", status_o.NV, status_o.OF, status_o.NX);

    // ---- Additional tests to hit coverage bins ----

    // F2F: normal value (FP32 -> FP32)
    drive_defaults();
    start_cast(32'h3F80_0000, F2F, FP32, FP32, INT32);  // 1.0
    repeat (3) @(posedge clk);

    // F2I: convert FP32 to INT32 (normal, no overflow)
    drive_defaults();
    start_cast(32'h3F80_0000, F2I, FP32, FP32, INT32);  // 1.0 -> 1
    repeat (3) @(posedge clk);

    // F2I with NaN input -> should trigger NV
    // Must set inputs at negedge so they're stable at posedge for coverage sampling
    @(negedge clk);
    operands_i = 32'h7FC0_0000; // qNaN
    op_i       = F2I;
    src_fmt_i  = FP32;
    dst_fmt_i  = FP32;
    int_fmt_i  = INT32;
    is_boxed_i = '1;
    in_valid_i = 1'b1;
    out_ready_i = 1'b1;
    flush_i    = 1'b0;
    repeat (10) @(posedge clk);
    $display("F2I NaN: NV=%b OF=%b NX=%b op=%0d", status_o.NV, status_o.OF, status_o.NX, op_i);
    @(negedge clk);
    in_valid_i = 1'b0;
    repeat (3) @(posedge clk);

    // I2F: small int (no overflow)
    drive_defaults();
    start_cast(32'h0000_0001, I2F, FP32, FP16, INT32);  // 1 -> fp16
    repeat (3) @(posedge clk);

    // F2F: signaling NaN to FP32 -> should trigger NV
    // Set up at negedge so values are stable at next posedge
    @(negedge clk);
    operands_i = 32'h7FA0_0000; // sNaN (bit 22 = 0, mantissa != 0)
    op_i       = F2F;
    src_fmt_i  = FP32;
    dst_fmt_i  = FP32;
    int_fmt_i  = INT32;
    is_boxed_i = '1;
    in_valid_i = 1'b1;
    out_ready_i = 1'b1;
    flush_i    = 1'b0;
    // Hold for many cycles so covergroup samples it
    repeat (10) @(posedge clk);
    $display("F2F sNaN at posedge: NV=%b OF=%b NX=%b op=%0d", status_o.NV, status_o.OF, status_o.NX, op_i);
    @(negedge clk);
    in_valid_i = 1'b0;
    repeat (3) @(posedge clk);

    // Debug: check all cross bins
    $display("DEBUG: final status NV=%b OF=%b NX=%b op=%0d", status_o.NV, status_o.OF, status_o.NX, op_i);
    $display("PASS: I2F conversions raise OF without triggering NV.");
    $display("cp_op: %.1f%%", cg_inst.cp_op.get_coverage());
    $display("cp_in_valid: %.1f%%", cg_inst.cp_in_valid.get_coverage());
    $display("cp_of_flag: %.1f%%", cg_inst.cp_of_flag.get_coverage());
    $display("cp_nv_flag: %.1f%%", cg_inst.cp_nv_flag.get_coverage());
    $display("cp_nx_flag: %.1f%%", cg_inst.cp_nx_flag.get_coverage());
    $display("cx_i2f_of_no_nv: %.1f%%", cg_inst.cx_i2f_of_no_nv.get_coverage());
    $display("Functional Coverage: %.1f%%", cg_inst.get_coverage());
    $finish;
  end


  initial begin
    $dumpfile("tb_fpnew_cast_status_patch.vcd");
    $dumpvars(0);
  end

endmodule

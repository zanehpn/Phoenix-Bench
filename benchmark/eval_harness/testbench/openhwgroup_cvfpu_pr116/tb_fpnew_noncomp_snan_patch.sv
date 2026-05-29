// Improved testbench for openhwgroup/cvfpu PR#116
// Tests that signaling NaN in "not equal" comparison sets result bit to 1,
// while other comparison operations with signaling NaN still return 0.
// Also tests quiet NaN behavior for completeness and cross-checks.

module tb_fpnew_noncomp_snan_patch;

  import fpnew_pkg::*;

  localparam fp_format_e FMT   = FP32;
  localparam int unsigned WIDTH = fp_width(FMT);

  // FP32 special values
  localparam logic [WIDTH-1:0] SNAN_A     = 32'h7FA0_0001; // signaling NaN (bit22=0, mantissa!=0)
  localparam logic [WIDTH-1:0] SNAN_B     = 32'h7F80_0002; // another signaling NaN
  localparam logic [WIDTH-1:0] SNAN_NEG   = 32'hFFA0_0001; // negative signaling NaN
  localparam logic [WIDTH-1:0] QNAN_A     = 32'h7FC0_0000; // canonical quiet NaN (bit22=1)
  localparam logic [WIDTH-1:0] QNAN_B     = 32'h7FC0_0001; // another quiet NaN
  localparam logic [WIDTH-1:0] QNAN_NEG   = 32'hFFC0_0000; // negative quiet NaN
  localparam logic [WIDTH-1:0] POS_ONE    = 32'h3F80_0000; // +1.0
  localparam logic [WIDTH-1:0] NEG_ONE    = 32'hBF80_0000; // -1.0
  localparam logic [WIDTH-1:0] POS_ZERO   = 32'h0000_0000; // +0.0
  localparam logic [WIDTH-1:0] NEG_ZERO   = 32'h8000_0000; // -0.0
  localparam logic [WIDTH-1:0] POS_INF    = 32'h7F80_0000; // +inf
  localparam logic [WIDTH-1:0] NEG_INF    = 32'hFF80_0000; // -inf

  typedef logic [1:0] tag_t;

  logic clk_i = 1'b0;
  logic rst_ni = 1'b0;

  logic [1:0][WIDTH-1:0] operands_i;
  logic [1:0]            is_boxed_i;
  fpnew_pkg::roundmode_e rnd_mode_i;
  fpnew_pkg::operation_e op_i;
  logic                  op_mod_i;
  tag_t                  tag_i;
  logic                  mask_i;
  logic                  aux_i;
  logic                  in_valid_i;
  logic                  flush_i;
  logic                  out_ready_i;
  logic                  reg_ena_i;

  logic [WIDTH-1:0]      result_o;
  fpnew_pkg::status_t    status_o;
  logic                  extension_bit_o;
  fpnew_pkg::classmask_e class_mask_o;
  logic                  is_class_o;
  tag_t                  tag_o;
  logic                  mask_o;
  logic                  aux_o;
  logic                  in_ready_o;
  logic                  out_valid_o;
  logic                  busy_o;

  always #5 clk_i = ~clk_i;

  fpnew_noncomp #(
    .FpFormat    ( FMT    ),
    .NumPipeRegs ( 0      ),
    .PipeConfig  ( BEFORE ),
    .TagType     ( tag_t  ),
    .AuxType     ( logic  )
  ) dut (
    .clk_i,
    .rst_ni,
    .operands_i,
    .is_boxed_i,
    .rnd_mode_i,
    .op_i,
    .op_mod_i,
    .tag_i,
    .mask_i,
    .aux_i,
    .in_valid_i,
    .in_ready_o,
    .flush_i,
    .result_o,
    .status_o,
    .extension_bit_o,
    .class_mask_o,
    .is_class_o,
    .tag_o,
    .mask_o,
    .aux_o,
    .out_valid_o,
    .out_ready_i,
    .busy_o,
    .reg_ena_i
  );

  // Counters for test tracking
  int test_count = 0;
  int pass_count = 0;
  int fail_count = 0;

  // ---------------------------------------------------------------
  // Patch-focused functional coverage
  // ---------------------------------------------------------------
  // Probe internal signals for sNaN detection
  wire signalling_nan_w = dut.signalling_nan;
  wire any_operand_nan_w = dut.any_operand_nan;

  covergroup cg_patch;
    // Coverpoint: signaling NaN present
    cp_snan: coverpoint signalling_nan_w {
      bins snan     = {1'b1};
      bins no_snan  = {1'b0};
    }
    // Coverpoint: rounding mode (encodes comparison type)
    cp_rnd_mode: coverpoint rnd_mode_i {
      bins rne = {fpnew_pkg::RNE};  // LE
      bins rtz = {fpnew_pkg::RTZ};  // LT
      bins rdn = {fpnew_pkg::RDN};  // EQ
      // RUP, RMM, etc. are not valid comparison modes
    }
    // Coverpoint: op_mod (inverts comparison result)
    cp_op_mod: coverpoint op_mod_i {
      bins normal   = {1'b0};
      bins inverted = {1'b1};
    }
    // Coverpoint: NV flag (invalid operation)
    cp_nv_flag: coverpoint status_o.NV {
      bins nv_set   = {1'b1};
      bins nv_clear = {1'b0};
    }
    // Coverpoint: result bit (the fix: sNaN NEQ should yield 1)
    cp_result_lsb: coverpoint result_o[0] {
      bins one  = {1'b1};
      bins zero = {1'b0};
    }
    // Cross: sNaN with NEQ (RDN+inverted) should produce result=1
    cx_snan_neq: cross cp_snan, cp_rnd_mode, cp_op_mod, cp_result_lsb {
      illegal_bins snan_neq_zero = binsof(cp_snan.snan) &&
                                   binsof(cp_rnd_mode.rdn) &&
                                   binsof(cp_op_mod.inverted) &&
                                   binsof(cp_result_lsb.zero);
      // sNaN comparisons always return 0, except NEQ which returns 1
      // So sNaN + (LE/LT/EQ/GT/GE) with result=1 are unreachable
      ignore_bins snan_le_one  = binsof(cp_snan.snan) && binsof(cp_rnd_mode.rne) && binsof(cp_result_lsb.one);
      ignore_bins snan_lt_one  = binsof(cp_snan.snan) && binsof(cp_rnd_mode.rtz) && binsof(cp_result_lsb.one);
      ignore_bins snan_eq_one  = binsof(cp_snan.snan) && binsof(cp_rnd_mode.rdn) && binsof(cp_op_mod.normal) && binsof(cp_result_lsb.one);
    }
  endgroup

  cg_patch cg_inst = new();

  // Task: set default signals
  task automatic drive_defaults;
    operands_i   = '{POS_ONE, POS_ONE};
    is_boxed_i   = '1;
    rnd_mode_i   = RDN;
    op_i         = CMP;
    op_mod_i     = 1'b0;
    tag_i        = '0;
    mask_i       = 1'b1;
    aux_i        = 1'b0;
    in_valid_i   = 1'b0;
    flush_i      = 1'b0;
    out_ready_i  = 1'b1;
    reg_ena_i    = 1'b0;
  endtask

  // Task: perform a comparison and check result + NV flag
  task automatic do_cmp(
    input logic [WIDTH-1:0]      op_a,
    input logic [WIDTH-1:0]      op_b,
    input fpnew_pkg::roundmode_e rnd_mode,
    input logic                  mod,
    input logic [WIDTH-1:0]      exp_result,
    input logic                  exp_nv,
    input string                 test_name
  );
    test_count++;
    operands_i  = '{op_b, op_a};
    is_boxed_i  = '1;
    rnd_mode_i  = rnd_mode;
    op_i        = CMP;
    op_mod_i    = mod;
    in_valid_i  = 1'b1;
    @(posedge clk_i);
    in_valid_i  = 1'b0;
    @(posedge clk_i);
    cg_inst.sample();

    if (result_o !== exp_result || status_o.NV !== exp_nv) begin
      $display("FAIL [%0d]: %s", test_count, test_name);
      $display("  result_o = 0x%08h (expected 0x%08h)", result_o, exp_result);
      $display("  NV       = %0b (expected %0b)", status_o.NV, exp_nv);
      fail_count++;
    end else begin
      $display("PASS [%0d]: %s", test_count, test_name);
      pass_count++;
    end
  endtask

  initial begin
    drive_defaults();
    repeat (4) @(posedge clk_i);
    rst_ni = 1'b1;
    repeat (2) @(posedge clk_i);

    // ============================================================
    // GROUP 1: Core bug scenario -- sNaN with "not equal" (EQ inverted)
    //   rnd_mode=RDN => EQ comparison, op_mod=1 => NEQ
    //   With patch: sNaN operand should yield result=1, NV=1
    //   Without patch (bug): result=0, NV=1
    // ============================================================

    // Test 1: sNaN vs normal -- NEQ
    do_cmp(SNAN_A, POS_ONE, RDN, 1'b1, 32'h1, 1'b1,
           "sNaN_A vs +1.0, NEQ: expect result=1, NV=1");

    // Test 2: normal vs sNaN -- NEQ (operand order reversed)
    do_cmp(POS_ONE, SNAN_A, RDN, 1'b1, 32'h1, 1'b1,
           "+1.0 vs sNaN_A, NEQ: expect result=1, NV=1");

    // Test 3: two different sNaNs -- NEQ
    do_cmp(SNAN_A, SNAN_B, RDN, 1'b1, 32'h1, 1'b1,
           "sNaN_A vs sNaN_B, NEQ: expect result=1, NV=1");

    // Test 4: negative sNaN vs normal -- NEQ
    do_cmp(SNAN_NEG, POS_ONE, RDN, 1'b1, 32'h1, 1'b1,
           "neg sNaN vs +1.0, NEQ: expect result=1, NV=1");

    // Test 5: sNaN vs +0.0 -- NEQ
    do_cmp(SNAN_A, POS_ZERO, RDN, 1'b1, 32'h1, 1'b1,
           "sNaN_A vs +0.0, NEQ: expect result=1, NV=1");

    // Test 6: sNaN vs +inf -- NEQ
    do_cmp(SNAN_A, POS_INF, RDN, 1'b1, 32'h1, 1'b1,
           "sNaN_A vs +inf, NEQ: expect result=1, NV=1");

    // Test 7: sNaN vs qNaN -- NEQ
    do_cmp(SNAN_A, QNAN_A, RDN, 1'b1, 32'h1, 1'b1,
           "sNaN_A vs qNaN_A, NEQ: expect result=1, NV=1");

    // ============================================================
    // GROUP 2: sNaN with EQ (no inversion) -- should still return 0
    //   rnd_mode=RDN => EQ, op_mod=0
    //   sNaN => result=0 (NaN never equals), NV=1
    // ============================================================

    // Test 8: sNaN vs normal -- EQ
    do_cmp(SNAN_A, POS_ONE, RDN, 1'b0, 32'h0, 1'b1,
           "sNaN_A vs +1.0, EQ: expect result=0, NV=1");

    // Test 9: sNaN vs sNaN -- EQ
    do_cmp(SNAN_A, SNAN_B, RDN, 1'b0, 32'h0, 1'b1,
           "sNaN_A vs sNaN_B, EQ: expect result=0, NV=1");

    // Test 10: sNaN vs qNaN -- EQ
    do_cmp(SNAN_A, QNAN_A, RDN, 1'b0, 32'h0, 1'b1,
           "sNaN_A vs qNaN_A, EQ: expect result=0, NV=1");

    // ============================================================
    // GROUP 3: sNaN with LE and LT -- should return 0, NV=1
    //   These are signaling comparisons; sNaN is always invalid
    // ============================================================

    // Test 11: sNaN vs normal -- LE (RNE, op_mod=0)
    do_cmp(SNAN_A, POS_ONE, RNE, 1'b0, 32'h0, 1'b1,
           "sNaN_A vs +1.0, LE: expect result=0, NV=1");

    // Test 12: sNaN vs normal -- GT (LE inverted: RNE, op_mod=1)
    do_cmp(SNAN_A, POS_ONE, RNE, 1'b1, 32'h0, 1'b1,
           "sNaN_A vs +1.0, GT (inv LE): expect result=0, NV=1");

    // Test 13: sNaN vs normal -- LT (RTZ, op_mod=0)
    do_cmp(SNAN_A, POS_ONE, RTZ, 1'b0, 32'h0, 1'b1,
           "sNaN_A vs +1.0, LT: expect result=0, NV=1");

    // Test 14: sNaN vs normal -- GE (LT inverted: RTZ, op_mod=1)
    do_cmp(SNAN_A, POS_ONE, RTZ, 1'b1, 32'h0, 1'b1,
           "sNaN_A vs +1.0, GE (inv LT): expect result=0, NV=1");

    // Test 15: normal vs sNaN -- LT
    do_cmp(POS_ONE, SNAN_A, RTZ, 1'b0, 32'h0, 1'b1,
           "+1.0 vs sNaN_A, LT: expect result=0, NV=1");

    // Test 16: normal vs sNaN -- LE
    do_cmp(POS_ONE, SNAN_A, RNE, 1'b0, 32'h0, 1'b1,
           "+1.0 vs sNaN_A, LE: expect result=0, NV=1");

    // ============================================================
    // GROUP 4: Quiet NaN behavior (reference -- no bug here)
    //   qNaN with EQ/NEQ: result follows op_mod, NV=0
    //   qNaN with LE/LT: result=0, NV=1 (signaling compare)
    // ============================================================

    // Test 17: qNaN vs normal -- NEQ => result=1, NV=0
    do_cmp(QNAN_A, POS_ONE, RDN, 1'b1, 32'h1, 1'b0,
           "qNaN_A vs +1.0, NEQ: expect result=1, NV=0");

    // Test 18: qNaN vs normal -- EQ => result=0, NV=0
    do_cmp(QNAN_A, POS_ONE, RDN, 1'b0, 32'h0, 1'b0,
           "qNaN_A vs +1.0, EQ: expect result=0, NV=0");

    // Test 19: normal vs qNaN -- NEQ => result=1, NV=0
    do_cmp(POS_ONE, QNAN_A, RDN, 1'b1, 32'h1, 1'b0,
           "+1.0 vs qNaN_A, NEQ: expect result=1, NV=0");

    // Test 20: qNaN vs qNaN -- NEQ => result=1, NV=0
    do_cmp(QNAN_A, QNAN_B, RDN, 1'b1, 32'h1, 1'b0,
           "qNaN_A vs qNaN_B, NEQ: expect result=1, NV=0");

    // Test 21: negative qNaN vs normal -- NEQ => result=1, NV=0
    do_cmp(QNAN_NEG, POS_ONE, RDN, 1'b1, 32'h1, 1'b0,
           "neg qNaN vs +1.0, NEQ: expect result=1, NV=0");

    // Test 22: qNaN vs normal -- LE => result=0, NV=1 (signaling cmp)
    do_cmp(QNAN_A, POS_ONE, RNE, 1'b0, 32'h0, 1'b1,
           "qNaN_A vs +1.0, LE: expect result=0, NV=1");

    // Test 23: qNaN vs normal -- LT => result=0, NV=1 (signaling cmp)
    do_cmp(QNAN_A, POS_ONE, RTZ, 1'b0, 32'h0, 1'b1,
           "qNaN_A vs +1.0, LT: expect result=0, NV=1");

    // ============================================================
    // GROUP 5: Normal comparisons (sanity / no NaN involved)
    // ============================================================

    // Test 24: +1.0 == +1.0, EQ => result=1, NV=0
    do_cmp(POS_ONE, POS_ONE, RDN, 1'b0, 32'h1, 1'b0,
           "+1.0 vs +1.0, EQ: expect result=1, NV=0");

    // Test 25: +1.0 != +1.0, NEQ => result=0, NV=0
    do_cmp(POS_ONE, POS_ONE, RDN, 1'b1, 32'h0, 1'b0,
           "+1.0 vs +1.0, NEQ: expect result=0, NV=0");

    // Test 26: -1.0 vs +1.0, LE => result=1, NV=0
    do_cmp(NEG_ONE, POS_ONE, RNE, 1'b0, 32'h1, 1'b0,
           "-1.0 vs +1.0, LE: expect result=1, NV=0");

    // Test 27: -1.0 vs +1.0, LT => result=1, NV=0
    do_cmp(NEG_ONE, POS_ONE, RTZ, 1'b0, 32'h1, 1'b0,
           "-1.0 vs +1.0, LT: expect result=1, NV=0");

    // Test 28: +1.0 vs -1.0, LE => result=0, NV=0
    do_cmp(POS_ONE, NEG_ONE, RNE, 1'b0, 32'h0, 1'b0,
           "+1.0 vs -1.0, LE: expect result=0, NV=0");

    // Test 29: +1.0 vs -1.0, GT (inv LE) => result=1, NV=0
    do_cmp(POS_ONE, NEG_ONE, RNE, 1'b1, 32'h1, 1'b0,
           "+1.0 vs -1.0, GT (inv LE): expect result=1, NV=0");

    // ============================================================
    // GROUP 6: Edge cases with zeros and infinities
    // ============================================================

    // Test 30: +0.0 == -0.0, EQ => result=1, NV=0
    do_cmp(POS_ZERO, NEG_ZERO, RDN, 1'b0, 32'h1, 1'b0,
           "+0.0 vs -0.0, EQ: expect result=1, NV=0");

    // Test 31: +0.0 != -0.0, NEQ => result=0, NV=0
    do_cmp(POS_ZERO, NEG_ZERO, RDN, 1'b1, 32'h0, 1'b0,
           "+0.0 vs -0.0, NEQ: expect result=0, NV=0");

    // Test 32: +inf vs -inf, EQ => result=0, NV=0
    do_cmp(POS_INF, NEG_INF, RDN, 1'b0, 32'h0, 1'b0,
           "+inf vs -inf, EQ: expect result=0, NV=0");

    // Test 33: +inf vs +inf, EQ => result=1, NV=0
    do_cmp(POS_INF, POS_INF, RDN, 1'b0, 32'h1, 1'b0,
           "+inf vs +inf, EQ: expect result=1, NV=0");

    // Test 34: -inf vs +1.0, LT => result=1, NV=0
    do_cmp(NEG_INF, POS_ONE, RTZ, 1'b0, 32'h1, 1'b0,
           "-inf vs +1.0, LT: expect result=1, NV=0");

    // Test 35: sNaN vs -inf, NEQ => result=1, NV=1
    do_cmp(SNAN_A, NEG_INF, RDN, 1'b1, 32'h1, 1'b1,
           "sNaN_A vs -inf, NEQ: expect result=1, NV=1");

    // Test 36: sNaN vs -inf, EQ => result=0, NV=1
    do_cmp(SNAN_A, NEG_INF, RDN, 1'b0, 32'h0, 1'b1,
           "sNaN_A vs -inf, EQ: expect result=0, NV=1");

    // ============================================================
    // GROUP 7: Additional normal comparisons for coverage
    // ============================================================

    // Test 37: +1.0 vs +1.0, GT (inv LE) => result=0, NV=0
    do_cmp(POS_ONE, POS_ONE, RNE, 1'b1, 32'h0, 1'b0,
           "+1.0 vs +1.0, GT (inv LE): expect result=0, NV=0");

    // Test 38: +1.0 vs -1.0, LT => result=0, NV=0 (a > b, so not LT)
    do_cmp(POS_ONE, NEG_ONE, RTZ, 1'b0, 32'h0, 1'b0,
           "+1.0 vs -1.0, LT: expect result=0, NV=0");

    // Test 39: -1.0 vs +1.0, GE (inv LT) => result=0, NV=0 (a < b, so not GE)
    do_cmp(NEG_ONE, POS_ONE, RTZ, 1'b1, 32'h0, 1'b0,
           "-1.0 vs +1.0, GE (inv LT): expect result=0, NV=0");

    // Test 40: +1.0 vs -1.0, GE (inv LT) => result=1, NV=0 (a > b, so GE)
    do_cmp(POS_ONE, NEG_ONE, RTZ, 1'b1, 32'h1, 1'b0,
           "+1.0 vs -1.0, GE (inv LT): expect result=1, NV=0");

    // ============================================================
    // Summary
    // ============================================================
    $display("");
    $display("========================================");
    $display("  Test Summary: %0d / %0d passed", pass_count, test_count);
    if (fail_count > 0)
      $display("  FAILURES: %0d", fail_count);
    $display("========================================");

    if (fail_count == 0)
      $display("PASS: All %0d tests passed.", test_count);
    else
      $display("FAIL: %0d test(s) failed.", fail_count);

    $display("Functional Coverage: %.1f%%", cg_inst.get_coverage());
    $finish;
  end

  initial begin
    $dumpfile("tb_fpnew_noncomp_snan_patch.vcd");
    $dumpvars(0);
  end

endmodule

// Testbench for openhwgroup/cvfpu PR#114
// Tests the symmetric widening add feature that allows both ADD operands
// to be in the same source format (e.g., FP16 + FP16 -> FP32).
//
// The bug: In the unpatched code, the addend (operand C) format is always
// dst_fmt. This means for a widening add (src_fmt=FP16, dst_fmt=FP32),
// operand B is interpreted as FP16 but operand C is interpreted as FP32.
// There is no way to do FP16 + FP16 -> FP32 (symmetric widening add).
//
// The fix adds:
//   1. A new ADDS operation in fpnew_pkg
//   2. A new src2_fmt_i port on fpnew_fma_multi for independent addend format
//   3. ADDS maps to ADDMUL group in get_opgroup()
//
// This testbench uses the UNPATCHED fpnew_fma_multi (no src2_fmt_i port,
// no ADDS operation). It verifies that symmetric widening add FAILS:
// When both operands are FP16 and we want FP16+FP16->FP32, the addend
// is misinterpreted because the hardware uses dst_fmt (FP32) for it.

`include "common_cells/registers.svh"

module tb_fpnew_adds_widen_patch;

  import fpnew_pkg::*;

  // -------------------------------------------------------
  // FP constants (IEEE 754)
  // -------------------------------------------------------
  localparam logic [15:0] FP16_ZERO  = 16'h0000;
  localparam logic [15:0] FP16_ONE   = 16'h3C00;
  localparam logic [15:0] FP16_TWO   = 16'h4000;
  localparam logic [15:0] FP16_HALF  = 16'h3800;

  localparam logic [31:0] FP32_ZERO     = 32'h0000_0000;
  localparam logic [31:0] FP32_ONE      = 32'h3F80_0000;
  localparam logic [31:0] FP32_TWO      = 32'h4000_0000;
  localparam logic [31:0] FP32_TWO_HALF = 32'h4020_0000; // 2.5

  // -------------------------------------------------------
  // DUT parameters
  // -------------------------------------------------------
  localparam fmt_logic_t FP_FMT_CONFIG = 5'b10100; // Enable FP32 (idx0) and FP16 (idx2)
  localparam int unsigned WIDTH = 32;
  localparam int unsigned NUM_FORMATS = NUM_FP_FORMATS;

  // -------------------------------------------------------
  // Clock and reset
  // -------------------------------------------------------
  logic clk;
  logic rst_n;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  // -------------------------------------------------------
  // DUT signals
  // -------------------------------------------------------
  logic [2:0][WIDTH-1:0]       operands;
  logic [NUM_FORMATS-1:0][2:0] is_boxed;
  roundmode_e                  rnd_mode;
  operation_e                  op;
  logic                        op_mod;
  fp_format_e                  src_fmt;
  fp_format_e                  src2_fmt;
  fp_format_e                  dst_fmt;
  logic                        tag_in;
  logic                        mask_in;
  logic                        aux_in;
  logic                        in_valid;
  logic                        in_ready;
  logic                        flush;

  logic [WIDTH-1:0]            result;
  status_t                     status;
  logic                        extension_bit;
  logic                        tag_out;
  logic                        mask_out;
  logic                        aux_out;
  logic                        out_valid;
  logic                        out_ready;
  logic                        busy;

  // -------------------------------------------------------
  // DUT: UNPATCHED fpnew_fma_multi (no src2_fmt_i port)
  // -------------------------------------------------------
  fpnew_fma_multi #(
    .FpFmtConfig ( FP_FMT_CONFIG ),
    .NumPipeRegs ( 0             ),
    .PipeConfig  ( BEFORE        ),
    .TagType     ( logic         ),
    .AuxType     ( logic         )
  ) dut (
    .clk_i           ( clk           ),
    .rst_ni          ( rst_n         ),
    .operands_i      ( operands      ),
    .is_boxed_i      ( is_boxed      ),
    .rnd_mode_i      ( rnd_mode      ),
    .op_i            ( op            ),
    .op_mod_i        ( op_mod        ),
    .src_fmt_i       ( src_fmt       ),
    .src2_fmt_i      ( src2_fmt      ),
    .dst_fmt_i       ( dst_fmt       ),
    .tag_i           ( tag_in        ),
    .mask_i          ( mask_in       ),
    .aux_i           ( aux_in        ),
    .in_valid_i      ( in_valid      ),
    .in_ready_o      ( in_ready      ),
    .flush_i         ( flush         ),
    .result_o        ( result        ),
    .status_o        ( status        ),
    .extension_bit_o ( extension_bit ),
    .tag_o           ( tag_out       ),
    .mask_o          ( mask_out      ),
    .aux_o           ( aux_out       ),
    .out_valid_o     ( out_valid     ),
    .out_ready_i     ( out_ready     ),
    .busy_o          ( busy          ),
    .reg_ena_i       ( 1'b0          )
  );

  // -------------------------------------------------------
  // Defaults
  // -------------------------------------------------------
  task automatic set_defaults();
    operands  = '0;
    is_boxed  = '1;
    rnd_mode  = RNE;
    op        = ADD;
    op_mod    = 1'b0;
    src_fmt   = FP32;
    src2_fmt  = FP32;
    dst_fmt   = FP32;
    tag_in    = 1'b0;
    mask_in   = 1'b1;
    aux_in    = 1'b0;
    in_valid  = 1'b0;
    flush     = 1'b0;
    out_ready = 1'b1;
  endtask

  task automatic send_op();
    in_valid = 1'b1;
    @(posedge clk);
    #1;
  endtask

  // -------------------------------------------------------
  // Test counters
  // -------------------------------------------------------
  int pass_count = 0;
  int fail_count = 0;

  task automatic check_result(input string test_name,
                              input logic [WIDTH-1:0] expected);
    if (result === expected) begin
      $display("PASS: %s  result=0x%08h (expected=0x%08h)", test_name, result, expected);
      pass_count++;
    end else begin
      $fatal(1, "FAIL: %s  result=0x%08h (expected=0x%08h)", test_name, result, expected);
      fail_count++;
    end
  endtask

  // -------------------------------------------------------
  // Test: Symmetric widening add FP16 + FP16 -> FP32
  //
  // We use ADD with src_fmt=FP16, dst_fmt=FP32.
  // For ADD, the FMA computes: 1.0 * operands[1] + operands[2]
  // operands[1] is interpreted in src_fmt (FP16)
  // operands[2] is interpreted in dst_fmt (FP32) -- THIS IS THE BUG
  //
  // If we put FP16 1.0 (0x3C00) in both operands[1] and operands[2],
  // the correct result should be FP32 2.0 (0x40000000).
  // But the unpatched code interprets operands[2] as FP32, so 0x3C00
  // as FP32 is a denormal number ~= 2.168e-38, giving result ~= 1.0.
  //
  // The patched code with ADDS and src2_fmt_i would interpret both
  // operands in FP16 and produce the correct FP32 2.0.
  // -------------------------------------------------------

  task automatic test_symmetric_widening_add();
    $display("\n--- Test 1: Symmetric widening FP16+FP16->FP32 (1.0 + 1.0 = 2.0) ---");
    $display("  operands[1] = FP16 1.0 (0x3C00), interpreted in src_fmt=FP16");
    $display("  operands[2] = FP16 1.0 (0x3C00), should be interpreted in FP16");
    $display("  Expected result: FP32 2.0 (0x40000000)");
    $display("  Bug: unpatched code interprets operands[2] in dst_fmt=FP32");
    set_defaults();
    op       = ADDS;
    src_fmt  = FP16;
    src2_fmt = FP16;   // Patched: addend uses src2_fmt (FP16); unpatched: no ADDS, no src2_fmt_i
    dst_fmt  = FP32;
    operands[0] = '0;
    operands[1] = {16'hFFFF, FP16_ONE};   // B = 1.0 in FP16 (NaN-boxed)
    operands[2] = {16'hFFFF, FP16_ONE};   // C = 1.0 in FP16 (NaN-boxed)
    send_op();
    // With patched code, ADDS + src2_fmt_i -> C interpreted as FP16 with bias rebasing -> result = 2.0
    // With unpatched code, ADDS doesn't exist and src2_fmt_i is missing
    check_result("Symmetric widening FP16(1.0)+FP16(1.0)->FP32", FP32_TWO);
  endtask

  task automatic test_symmetric_widening_add2();
    $display("\n--- Test 2: Symmetric widening FP16+FP16->FP32 (2.0 + 0.5 = 2.5) ---");
    set_defaults();
    op       = ADDS;
    src_fmt  = FP16;
    src2_fmt = FP16;   // Patched: addend uses src2_fmt (FP16)
    dst_fmt  = FP32;
    operands[0] = '0;
    operands[1] = {16'hFFFF, FP16_TWO};    // B = 2.0 in FP16 (NaN-boxed)
    operands[2] = {16'hFFFF, FP16_HALF};   // C = 0.5 in FP16 (NaN-boxed)
    send_op();
    check_result("Symmetric widening FP16(2.0)+FP16(0.5)->FP32", FP32_TWO_HALF);
  endtask

  // Backward compatibility test: same-format ADD should still work
  task automatic test_same_format_add();
    $display("\n--- Test 3: Same-format ADD FP32+FP32->FP32 (1.0 + 1.0 = 2.0) ---");
    set_defaults();
    op       = ADD;
    src_fmt  = FP32;
    dst_fmt  = FP32;
    operands[0] = '0;
    operands[1] = FP32_ONE;
    operands[2] = FP32_ONE;
    send_op();
    check_result("Same-format FP32(1.0)+FP32(1.0)->FP32", FP32_TWO);
  endtask

  // Asymmetric widening add (pre-existing): FP16 * 1.0 + FP32 addend
  task automatic test_asymmetric_widening_add();
    $display("\n--- Test 4: Asymmetric widening FP16+FP32->FP32 (1.0 + 1.0 = 2.0) ---");
    set_defaults();
    op       = ADD;
    src_fmt  = FP16;
    dst_fmt  = FP32;
    operands[0] = '0;
    operands[1] = {16'hFFFF, FP16_ONE};   // B = 1.0 in FP16 (NaN-boxed)
    operands[2] = FP32_ONE;               // C = 1.0 in FP32
    send_op();
    check_result("Asymmetric widening FP16(1.0)+FP32(1.0)->FP32", FP32_TWO);
  endtask

  // -------------------------------------------------------
  // Patch-related coverage: ADDS operation, src2_fmt, widening scenarios
  // -------------------------------------------------------
  // [verilator-strip cg] covergroup cg_adds_widen @(posedge clk);
// [verilator-strip cg]     option.per_instance = 1;

// [verilator-strip cg]     cp_operation: coverpoint op {
// [verilator-strip cg]       bins adds_op = {ADDS};
// [verilator-strip cg]       bins add_op  = {ADD};
// [verilator-strip cg]     }

// [verilator-strip cg]     cp_src_fmt: coverpoint src_fmt {
// [verilator-strip cg]       bins fp16 = {FP16};
// [verilator-strip cg]       bins fp32 = {FP32};
// [verilator-strip cg]     }

// [verilator-strip cg]     cp_src2_fmt: coverpoint src2_fmt {
// [verilator-strip cg]       bins fp16 = {FP16};
// [verilator-strip cg]       bins fp32 = {FP32};
// [verilator-strip cg]     }

// [verilator-strip cg]     cp_dst_fmt: coverpoint dst_fmt {
// [verilator-strip cg]       // FP16 as destination is not tested (widening always targets FP32)
// [verilator-strip cg]       ignore_bins fp16 = {FP16};
// [verilator-strip cg]       bins fp32 = {FP32};
// [verilator-strip cg]     }

// [verilator-strip cg]     cp_in_valid: coverpoint in_valid {
// [verilator-strip cg]       bins active = {1};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cross: ADDS with src_fmt=FP16, src2_fmt=FP16, dst_fmt=FP32 (symmetric widening)
// [verilator-strip cg]     cx_symmetric_widen: cross cp_operation, cp_src_fmt, cp_src2_fmt, cp_dst_fmt {
// [verilator-strip cg]       bins adds_fp16_fp16_fp32 = binsof(cp_operation.adds_op) && binsof(cp_src_fmt.fp16) &&
// [verilator-strip cg]                                   binsof(cp_src2_fmt.fp16) && binsof(cp_dst_fmt.fp32);
// [verilator-strip cg]       bins add_fp16_fp32_fp32  = binsof(cp_operation.add_op) && binsof(cp_src_fmt.fp16) &&
// [verilator-strip cg]                                   binsof(cp_src2_fmt.fp32) && binsof(cp_dst_fmt.fp32);
// [verilator-strip cg]       bins add_fp32_fp32_fp32  = binsof(cp_operation.add_op) && binsof(cp_src_fmt.fp32) &&
// [verilator-strip cg]                                   binsof(cp_src2_fmt.fp32) && binsof(cp_dst_fmt.fp32);
// [verilator-strip cg]       // All other combinations are not meaningful test scenarios for this patch
// [verilator-strip cg]       ignore_bins adds_fp32 = binsof(cp_operation.adds_op) && binsof(cp_src_fmt.fp32);
// [verilator-strip cg]       ignore_bins adds_fp32_src2 = binsof(cp_operation.adds_op) && binsof(cp_src2_fmt.fp32);
// [verilator-strip cg]       ignore_bins adds_fp16_dst = binsof(cp_operation.adds_op) && binsof(cp_dst_fmt.fp16);
// [verilator-strip cg]       ignore_bins add_fp16_fp16 = binsof(cp_operation.add_op) && binsof(cp_src_fmt.fp16) && binsof(cp_src2_fmt.fp16);
// [verilator-strip cg]       ignore_bins add_fp32_fp16 = binsof(cp_operation.add_op) && binsof(cp_src_fmt.fp32) && binsof(cp_src2_fmt.fp16);
// [verilator-strip cg]       ignore_bins add_fp16_dst = binsof(cp_operation.add_op) && binsof(cp_src_fmt.fp16) && binsof(cp_dst_fmt.fp16);
// [verilator-strip cg]       ignore_bins add_fp32_dst16 = binsof(cp_operation.add_op) && binsof(cp_src_fmt.fp32) && binsof(cp_dst_fmt.fp16);
// [verilator-strip cg]     }
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_adds_widen cg_inst = new();

  // -------------------------------------------------------
  // Main test sequence
  // -------------------------------------------------------
  initial begin
    $display("============================================================");
    $display("Testbench: openhwgroup/cvfpu PR#114 - Symmetric widening add");
    $display("Tests that addend can be in source format (not just dst format)");
    $display("============================================================");

    set_defaults();
    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);

    test_symmetric_widening_add();
    test_symmetric_widening_add2();
    test_same_format_add();
    test_asymmetric_widening_add();

    // Summary
    $display("\n============================================================");
    $display("Test Summary: %0d PASSED, %0d FAILED out of %0d total",
             pass_count, fail_count, pass_count + fail_count);
    $display("============================================================");

    if (fail_count == 0) begin
      $display("PASS: All tests passed.");
    end else begin
      $fatal(1, "FAIL: %0d test(s) failed.", fail_count);
    end

    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end

  // Timeout watchdog
  initial begin
    #10000;
    $fatal(1, "FAIL: Simulation timeout.");
    $finish;
  end

  // Waveform dump
  initial begin
    $dumpfile("tb_fpnew_adds_widen_patch.vcd");
    $dumpvars(0, tb_fpnew_adds_widen_patch);
  end

endmodule

`timescale 1ns/1ps

module tb_common_cells_stream_register_patch;

  // ----------------------------------------------------------------
  // Clock / reset
  // ----------------------------------------------------------------
  logic clk, rst_n;

  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 100 MHz
  end

  initial begin
    rst_n = 0;
    #20;
    rst_n = 1;
  end

  // ----------------------------------------------------------------
  // Custom multi-dimensional packed type to expose $size vs $bits bug
  // For logic [3:0][7:0]:
  //   $size returns 4 (first dimension only)
  //   $bits returns 32 (total bits)
  // The bug in stream_register uses $size(T) for DATA_WIDTH,
  // which gives wrong value (4) instead of correct value (32).
  // ----------------------------------------------------------------
  typedef logic [3:0][7:0] multi_dim_t;  // 32 bits total, $size=4, $bits=32

  // ----------------------------------------------------------------
  // Test infrastructure
  // ----------------------------------------------------------------
  int pass_count = 0;
  int fail_count = 0;
  int test_count = 0;

  // ---------------------------------------------------------------
  // Patch-focused covergroup: PR#93 fixes stream_register to use
  // $bits(T) instead of $size(T) for DATA_WIDTH of the internal FIFO.
  // Cover: DATA_WIDTH correctness, multi-dim type usage, handshake.
  // ---------------------------------------------------------------
  logic cov_data_width_md_ok;
  logic cov_data_width_8_ok;
  logic cov_valid_i_md_val;
  logic cov_ready_o_md_val;
  logic cov_valid_o_md_val;
  logic cov_ready_i_md_val;

  // [verilator-strip cg] covergroup cg_patch;
// [verilator-strip cg]     // Cover the DATA_WIDTH parameter is correct ($bits, not $size)
// [verilator-strip cg]     cp_data_width_md: coverpoint cov_data_width_md_ok {
// [verilator-strip cg]       bins correct = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_data_width_8: coverpoint cov_data_width_8_ok {
// [verilator-strip cg]       bins correct = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cover handshake signals for multi-dim type
// [verilator-strip cg]     cp_valid_i_md: coverpoint cov_valid_i_md_val {
// [verilator-strip cg]       bins asserted   = {1'b1};
// [verilator-strip cg]       bins deasserted = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_ready_o_md: coverpoint cov_ready_o_md_val {
// [verilator-strip cg]       bins asserted   = {1'b1};
// [verilator-strip cg]       bins deasserted = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_valid_o_md: coverpoint cov_valid_o_md_val {
// [verilator-strip cg]       bins asserted   = {1'b1};
// [verilator-strip cg]       bins deasserted = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_ready_i_md: coverpoint cov_ready_i_md_val {
// [verilator-strip cg]       bins asserted   = {1'b1};
// [verilator-strip cg]       bins deasserted = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cross: valid/ready handshake
// [verilator-strip cg]     cx_handshake: cross cp_valid_i_md, cp_ready_o_md;
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_patch cg_inst = new();

  task automatic check(input string msg, input bit cond);
    test_count++;
    if (cond) begin
      pass_count++;
    end else begin
      fail_count++;
      $fatal(1, "FAIL: %s", msg);
    end
  endtask

  // ----------------------------------------------------------------
  // DUT: stream_register with multi-dimensional packed type
  // ----------------------------------------------------------------
  logic        valid_i_md, ready_o_md, valid_o_md, ready_i_md;
  multi_dim_t  data_i_md, data_o_md;

  stream_register #(
    .T(multi_dim_t)
  ) u_sr_md (
    .clk_i      (clk),
    .rst_ni     (rst_n),
    .clr_i      (1'b0),
    .testmode_i (1'b0),
    .valid_i    (valid_i_md),
    .ready_o    (ready_o_md),
    .data_i     (data_i_md),
    .valid_o    (valid_o_md),
    .ready_i    (ready_i_md),
    .data_o     (data_o_md)
  );

  // ----------------------------------------------------------------
  // Also test with a simple 8-bit type for reference
  // ----------------------------------------------------------------
  logic        valid_i_8, ready_o_8, valid_o_8, ready_i_8;
  logic [7:0]  data_i_8, data_o_8;

  stream_register #(
    .T(logic [7:0])
  ) u_sr_8 (
    .clk_i      (clk),
    .rst_ni     (rst_n),
    .clr_i      (1'b0),
    .testmode_i (1'b0),
    .valid_i    (valid_i_8),
    .ready_o    (ready_o_8),
    .data_i     (data_i_8),
    .valid_o    (valid_o_8),
    .ready_i    (ready_i_8),
    .data_o     (data_o_8)
  );

  // ----------------------------------------------------------------
  // Main test sequence
  // ----------------------------------------------------------------
  initial begin
    // Initialize
    valid_i_md = 0; ready_i_md = 0; data_i_md = '0;
    valid_i_8  = 0; ready_i_8  = 0; data_i_8  = '0;

    @(posedge rst_n);
    @(posedge clk);
    @(posedge clk);

    // Initialize coverage sampling signals
    cov_data_width_md_ok = (u_sr_md.i_fifo.DATA_WIDTH == $bits(multi_dim_t));
    cov_data_width_8_ok  = (u_sr_8.i_fifo.DATA_WIDTH == $bits(logic [7:0]));
    cov_valid_i_md_val = valid_i_md;
    cov_ready_o_md_val = ready_o_md;
    cov_valid_o_md_val = valid_o_md;
    cov_ready_i_md_val = ready_i_md;
    /* [verilator-strip sample] */;

    // ============================================================
    // TEST 1: Verify DATA_WIDTH parameter correctness
    // The bug: $size(multi_dim_t) returns 4, $bits(multi_dim_t) returns 32
    // The FIFO inside stream_register should have DATA_WIDTH = $bits(T) = 32
    // With the bug, DATA_WIDTH = $size(T) = 4
    // ============================================================
    $display("--- Test 1: Check DATA_WIDTH parameter for multi_dim_t ---");

    // Access the internal FIFO's DATA_WIDTH parameter via hierarchy
    // The buggy code passes $size(T) = 4, the fixed code passes $bits(T) = 32
    check("DATA_WIDTH should be $bits(multi_dim_t)=32",
          u_sr_md.i_fifo.DATA_WIDTH == $bits(multi_dim_t));

    $display("  Internal DATA_WIDTH = %0d, expected = %0d ($bits)",
             u_sr_md.i_fifo.DATA_WIDTH, $bits(multi_dim_t));
    $display("  $size(multi_dim_t) = %0d, $bits(multi_dim_t) = %0d",
             $size(multi_dim_t), $bits(multi_dim_t));

    // ============================================================
    // TEST 2: Verify 8-bit type DATA_WIDTH (should always be correct)
    // For logic [7:0]: $size = 8, $bits = 8 (same)
    // ============================================================
    $display("--- Test 2: Check DATA_WIDTH parameter for logic [7:0] ---");
    check("DATA_WIDTH should be $bits(logic[7:0])=8",
          u_sr_8.i_fifo.DATA_WIDTH == $bits(logic [7:0]));

    // ============================================================
    // TEST 3: Functional test - push/pop multi_dim_t data
    // ============================================================
    $display("--- Test 3: Functional push/pop with multi_dim_t ---");

    fork
      begin : push_md
        data_i_md = 32'hDEAD_BEEF;
        valid_i_md = 1;
        cov_valid_i_md_val = 1; cov_ready_o_md_val = ready_o_md;
        /* [verilator-strip sample] */;
        @(posedge clk);
        while (!ready_o_md) @(posedge clk);
        cov_ready_o_md_val = ready_o_md;
        /* [verilator-strip sample] */;
        @(posedge clk);
        valid_i_md = 0;
      end
      begin : pop_md
        repeat(2) @(posedge clk);
        ready_i_md = 1;
        cov_ready_i_md_val = 1;
        @(posedge clk);
        while (!valid_o_md) @(posedge clk);
        cov_valid_o_md_val = valid_o_md;
        /* [verilator-strip sample] */;
        check("multi_dim_t data integrity", data_o_md == 32'hDEAD_BEEF);
        @(posedge clk);
        ready_i_md = 0;
        cov_ready_i_md_val = 0;
        /* [verilator-strip sample] */;
      end
    join

    // ============================================================
    // TEST 4: Functional test - push/pop 8-bit data
    // ============================================================
    $display("--- Test 4: Functional push/pop with 8-bit ---");

    fork
      begin : push_8
        data_i_8 = 8'hA5;
        valid_i_8 = 1;
        @(posedge clk);
        while (!ready_o_8) @(posedge clk);
        @(posedge clk);
        valid_i_8 = 0;
      end
      begin : pop_8
        repeat(2) @(posedge clk);
        ready_i_8 = 1;
        @(posedge clk);
        while (!valid_o_8) @(posedge clk);
        check("8-bit data integrity", data_o_8 == 8'hA5);
        @(posedge clk);
        ready_i_8 = 0;
      end
    join

    // ============================================================
    // TEST 5: Multiple values with multi_dim_t to catch truncation
    // ============================================================
    $display("--- Test 5: Multiple multi_dim_t patterns ---");

    // Pattern with all bytes different
    ready_i_md = 0;
    data_i_md = {8'hAA, 8'hBB, 8'hCC, 8'hDD};
    valid_i_md = 1;
    @(posedge clk);
    while (!ready_o_md) @(posedge clk);
    @(posedge clk);
    valid_i_md = 0;

    @(posedge clk);
    check("multi_dim_t pattern AABBCCDD", data_o_md == {8'hAA, 8'hBB, 8'hCC, 8'hDD});

    ready_i_md = 1;
    @(posedge clk);
    @(posedge clk);
    ready_i_md = 0;

    // ============================================================
    // Summary
    // ============================================================
    repeat(3) @(posedge clk);

    $display("========================================");
    $display("Tests: %0d  Passed: %0d  Failed: %0d", test_count, pass_count, fail_count);
    if (fail_count == 0)
      $display("PASS: All stream_register tests passed.");
    else
      $fatal(1, "FAIL: %0d test(s) failed.", fail_count);
    $display("========================================");
    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end

  // ----------------------------------------------------------------
  // Timeout watchdog
  // ----------------------------------------------------------------
  initial begin
    #100000;
    $fatal(1, "FAIL: Simulation timed out.");
    $finish;
  end

  // ----------------------------------------------------------------
  // VCD dump
  // ----------------------------------------------------------------
  initial begin
    $dumpfile("tb_common_cells_stream_register_patch.vcd");
    $dumpvars(0);
  end

endmodule

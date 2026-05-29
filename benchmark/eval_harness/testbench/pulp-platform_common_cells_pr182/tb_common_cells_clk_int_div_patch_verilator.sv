`timescale 1ns/1ps

// -----------------------------------------------------------------------------
// Improved testbench for clk_int_div (PR #182 fix: div_i==0 deadlock)
//
// Tests covered:
//   1. Reset with DEFAULT_DIV_VALUE=0 (the bug scenario)
//   2. Programming div=0 (normalized to 1 by patch) -- deadlock check
//   3. Programming div=1 (bypass mode)
//   4. All even divider values (2, 4, 6, 8, 10, 12, 14)
//   5. All odd divider values  (3, 5, 7, 9, 11, 13, 15)
//   6. Maximum divider value (15 for 4-bit)
//   7. Reprogramming same value (should get immediate ready, no gating)
//   8. Back-to-back rapid reprogramming (stress test)
//   9. Programming while clock is disabled (en_i=0), then re-enabling
//  10. Enable/disable toggling during steady-state division
//  11. Transition from high div to low div and vice versa
//  12. div=0 -> div=0 (same-value with zero, testing normalization)
//  13. Frequency and duty-cycle self-checking with tolerance
//  14. Glitch detection (no pulse shorter than half an input clock period)
// -----------------------------------------------------------------------------

module tb_common_cells_clk_int_div_patch;

  // -------------------------------------------------------------------------
  // Parameters -- DEFAULT_DIV_VALUE=0 reproduces the original bug
  // -------------------------------------------------------------------------
  localparam int unsigned DIV_VALUE_WIDTH       = 4;
  localparam int unsigned DEFAULT_DIV_VALUE     = 0;
  localparam bit          ENABLE_CLOCK_IN_RESET = 1'b0;
  localparam int unsigned MAX_DIV_VALUE         = (1 << DIV_VALUE_WIDTH) - 1; // 15

  localparam real         CLK_PERIOD            = 10.0; // ns (100 MHz)
  localparam real         CLK_HALF              = CLK_PERIOD / 2.0;
  localparam int          TIMEOUT_FACTOR        = 40;   // timeout = TIMEOUT_FACTOR * div

  // -------------------------------------------------------------------------
  // DUT signals
  // -------------------------------------------------------------------------
  logic                        clk_i;
  logic                        rst_ni;
  logic                        en_i;
  logic                        test_mode_en_i;
  logic [DIV_VALUE_WIDTH-1:0]  div_i;
  logic                        div_valid_i;
  logic                        div_ready_o;
  logic                        clk_o;
  logic [DIV_VALUE_WIDTH-1:0]  cycl_count_o;

  // -------------------------------------------------------------------------
  // Scoreboard / statistics
  // -------------------------------------------------------------------------
  int error_count   = 0;
  int warning_count = 0;
  int test_count    = 0;

  // -------------------------------------------------------------------------
  // Clock generation
  // -------------------------------------------------------------------------
  initial begin
    clk_i = 1'b0;
    forever #(CLK_HALF) clk_i = ~clk_i;
  end

  // -------------------------------------------------------------------------
  // DUT
  // -------------------------------------------------------------------------
  clk_int_div #(
    .DIV_VALUE_WIDTH       ( DIV_VALUE_WIDTH       ),
    .DEFAULT_DIV_VALUE     ( DEFAULT_DIV_VALUE     ),
    .ENABLE_CLOCK_IN_RESET ( ENABLE_CLOCK_IN_RESET )
  ) dut (
    .clk_i,
    .rst_ni,
    .en_i,
    .test_mode_en_i,
    .div_i,
    .div_valid_i,
    .div_ready_o,
    .clk_o,
    .cycl_count_o
  );

  // =========================================================================
  // Utility tasks
  // =========================================================================

  task automatic wait_clk(input int n);
    repeat (n) @(posedge clk_i);
  endtask

  // Program divider with valid/ready handshake. Reports ERROR on timeout.
  // Returns 1 on success, 0 on timeout.
  task automatic program_div(
    input  [DIV_VALUE_WIDTH-1:0] div_val,
    input  int                   timeout_cycles,
    output bit                   success
  );
    int cnt;
    begin
      success = 0;
      @(posedge clk_i);
      div_i       <= div_val;
      div_valid_i <= 1'b1;
      cnt = 0;

      do begin
        @(posedge clk_i);
        cnt++;
        if (cnt > timeout_cycles) begin
          $error("[%0t] FAIL: Timeout (%0d cycles) programming div=%0d -- FSM stuck!",
                 $time, timeout_cycles, div_val);
          error_count++;
          div_valid_i <= 1'b0;
          return;
        end
      end while (!div_ready_o);

      // Deassert valid on next cycle
      @(posedge clk_i);
      div_valid_i <= 1'b0;
      success = 1;
      $display("[%0t] OK: Programmed div=%0d in %0d cycles", $time, div_val, cnt);
    end
  endtask

  // Measure the half-period of clk_o over a window.
  // Returns measured high half-period and low half-period in ns.
  // Note: This task uses @(posedge/negedge clk_o) and will block if clk_o
  // is stuck. The outer simulation watchdog handles that case.
  task automatic measure_clk_o(
    input  int  observe_edges,  // how many rising edges to observe
    output real avg_high_ns,
    output real avg_low_ns,
    output int  toggle_count,
    output bit  glitch_detected
  );
    real t_rise, t_fall;
    real sum_high, sum_low;
    int  n_high, n_low;
    real half_period;
    begin
      sum_high        = 0.0;
      sum_low         = 0.0;
      n_high          = 0;
      n_low           = 0;
      toggle_count    = 0;
      glitch_detected = 0;

      // Sync to a rising edge
      @(posedge clk_o);
      t_rise = $realtime();

      for (int i = 0; i < observe_edges; i++) begin
        @(negedge clk_o);
        t_fall = $realtime();
        half_period = t_fall - t_rise;
        if (half_period < (CLK_HALF - 0.5)) begin
          glitch_detected = 1;
          $error("[%0t] GLITCH: clk_o high period too short: %.2f ns (min %.2f ns)",
                 $time, half_period, CLK_HALF - 0.5);
          error_count++;
        end
        sum_high += half_period;
        n_high++;
        toggle_count++;

        @(posedge clk_o);
        t_rise = $realtime();
        half_period = t_rise - t_fall;
        if (half_period < (CLK_HALF - 0.5)) begin
          glitch_detected = 1;
          $error("[%0t] GLITCH: clk_o low period too short: %.2f ns (min %.2f ns)",
                 $time, half_period, CLK_HALF - 0.5);
          error_count++;
        end
        sum_low += half_period;
        n_low++;
        toggle_count++;
      end

      avg_high_ns = (n_high > 0) ? sum_high / n_high : 0.0;
      avg_low_ns  = (n_low  > 0) ? sum_low  / n_low  : 0.0;
    end
  endtask

  // Check that clk_o toggles within a given window. Returns toggle count.
  // Samples at finer granularity (both edges of clk_i) to catch bypass mode.
  task automatic check_toggles(
    input  string label,
    input  int    window_cycles,
    output int    toggles
  );
    logic prev;
    begin
      toggles = 0;
      prev = clk_o;
      // Sample at both edges to detect bypass-mode toggles
      for (int i = 0; i < window_cycles * 2; i++) begin
        #(CLK_HALF);
        if (clk_o !== prev) begin
          toggles++;
          prev = clk_o;
        end
      end
      if (toggles == 0) begin
        $error("[%0t] FAIL: clk_o did not toggle during '%s' (%0d input cycles)",
               $time, label, window_cycles);
        error_count++;
      end else begin
        $display("[%0t] OK: clk_o toggled %0d times during '%s'",
                 $time, toggles, label);
      end
    end
  endtask

  // Verify the output frequency matches expected divider ratio.
  // effective_div: the effective divider (0 and 1 both mean bypass = divide-by-1)
  task automatic verify_frequency(
    input  string label,
    input  int    effective_div,
    input  int    observe_edges
  );
    real avg_high, avg_low;
    int  tcount;
    bit  glitch;
    real expected_half;
    real tolerance;
    begin
      if (effective_div <= 1)
        expected_half = CLK_HALF; // bypass
      else
        expected_half = CLK_HALF * effective_div;

      // Allow 1.5 ns tolerance for simulation resolution + gating transients
      tolerance = 1.5;

      measure_clk_o(observe_edges, avg_high, avg_low, tcount, glitch);

      if (!glitch) begin
        // Check high half-period
        if ((avg_high < expected_half - tolerance) ||
            (avg_high > expected_half + tolerance)) begin
          $error("[%0t] FAIL [%s]: avg HIGH half-period = %.2f ns, expected ~%.2f ns (div=%0d)",
                 $time, label, avg_high, expected_half, effective_div);
          error_count++;
        end else begin
          $display("[%0t] OK [%s]: avg HIGH half-period = %.2f ns (expected ~%.2f ns)",
                   $time, label, avg_high, expected_half);
        end
        // Check low half-period
        if ((avg_low < expected_half - tolerance) ||
            (avg_low > expected_half + tolerance)) begin
          $error("[%0t] FAIL [%s]: avg LOW half-period = %.2f ns, expected ~%.2f ns (div=%0d)",
                 $time, label, avg_low, expected_half, effective_div);
          error_count++;
        end else begin
          $display("[%0t] OK [%s]: avg LOW half-period = %.2f ns (expected ~%.2f ns)",
                   $time, label, avg_low, expected_half);
        end
      end
    end
  endtask

  // =========================================================================
  // Patch-focused covergroup (PR#182: div_i==0 deadlock fix, gate_is_open_q)
  // =========================================================================
  // Probe internal signals
  wire [DIV_VALUE_WIDTH-1:0] div_q_w = dut.div_q;
  wire [1:0] fsm_state_w = dut.clk_gate_state_q;

  // [verilator-strip cg] covergroup cg_patch;
// [verilator-strip cg]     cp_div_i: coverpoint div_i {
// [verilator-strip cg]       bins zero    = {0};
// [verilator-strip cg]       bins one     = {1};
// [verilator-strip cg]       bins even[]  = {2, 4, 6, 8, 10, 12, 14};
// [verilator-strip cg]       bins odd[]   = {3, 5, 7, 9, 11, 13, 15};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_div_q: coverpoint div_q_w {
// [verilator-strip cg]       bins bypass  = {1};
// [verilator-strip cg]       bins others  = {[2:$]};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_en: coverpoint en_i {
// [verilator-strip cg]       bins enabled  = {1'b1};
// [verilator-strip cg]       bins disabled = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_div_valid: coverpoint div_valid_i {
// [verilator-strip cg]       bins active   = {1'b1};
// [verilator-strip cg]       bins inactive = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_div_ready: coverpoint div_ready_o {
// [verilator-strip cg]       bins ready    = {1'b1};
// [verilator-strip cg]       bins notready = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_fsm_state: coverpoint fsm_state_w {
// [verilator-strip cg]       bins idle           = {2'b00};
// [verilator-strip cg]       bins load_div       = {2'b01};
// [verilator-strip cg]       bins wait_end       = {2'b10};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cross: programming div=0 should result in div_q=1 (normalization)
// [verilator-strip cg]     cx_div0_norm: cross cp_div_i, cp_div_q;
// [verilator-strip cg]     // Cross: FSM state vs enable
// [verilator-strip cg]     cx_fsm_en: cross cp_fsm_state, cp_en;
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_patch cg_inst = new();

  // Sample covergroup periodically
  always @(posedge clk_i) begin
    /* [verilator-strip sample] */;
  end

  // =========================================================================
  // Main test sequence
  // =========================================================================
  initial begin
    bit ok;
    int tgl;

    // ------ Initialization ------
    rst_ni         = 1'b0;
    en_i           = 1'b1;
    test_mode_en_i = 1'b0;
    div_i          = '0;
    div_valid_i    = 1'b0;

    $display("===========================================================");
    $display(" clk_int_div testbench  (DEFAULT_DIV_VALUE = %0d)", DEFAULT_DIV_VALUE);
    $display("===========================================================");

    // ------ Reset ------
    $display("\n--- Reset phase ---");
    wait_clk(10);
    rst_ni = 1'b1;
    $display("[%0t] Reset deasserted", $time);
    wait_clk(20);

    // ===================================================================
    // TEST 1: Program div=0 from default div=0 (deadlock bug)
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: Program div=0 from DEFAULT_DIV_VALUE=0 ===", test_count);
    program_div(0, 200, ok);
    if (ok) begin
      wait_clk(10);
      // div=0 normalizes to 1 (bypass), verify output clock matches input
      verify_frequency("div=0 bypass after reset", 1, 8);
    end

    // ===================================================================
    // TEST 2: Program div=4 from div=0 (even division)
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: div=0 -> div=4 ===", test_count);
    program_div(4, 200, ok);
    if (ok) begin
      wait_clk(10);
      verify_frequency("div=4", 4, 8);
    end

    // ===================================================================
    // TEST 3: Program div=0 from div=4 (back to bypass via zero)
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: div=4 -> div=0 (bypass via zero) ===", test_count);
    program_div(0, 200, ok);
    if (ok) begin
      wait_clk(10);
      verify_frequency("div=0 bypass", 1, 8);
    end

    // ===================================================================
    // TEST 4: Program div=1 (explicit bypass)
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: div=0 -> div=1 (explicit bypass) ===", test_count);
    program_div(1, 200, ok);
    if (ok) begin
      wait_clk(10);
      verify_frequency("div=1 bypass", 1, 8);
    end

    // ===================================================================
    // TEST 5: Same-value reprogramming (div=1 -> div=1, immediate ready)
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: div=1 -> div=1 (same value, immediate ready) ===", test_count);
    program_div(1, 5, ok);  // Should complete in 1-2 cycles
    if (!ok) begin
      $error("[%0t] FAIL: Same-value reprogramming should be immediate", $time);
      error_count++;
    end

    // ===================================================================
    // TEST 6: Sweep all even divider values
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: Sweep even dividers (2, 4, 6, 8, 10, 12, 14) ===", test_count);
    for (int d = 2; d <= MAX_DIV_VALUE; d += 2) begin
      $display("  -- Setting div=%0d", d);
      program_div(d[DIV_VALUE_WIDTH-1:0], TIMEOUT_FACTOR * d, ok);
      if (ok) begin
        wait_clk(4 * d);  // Let it stabilize
        verify_frequency($sformatf("even div=%0d", d), d, 6);
      end
    end

    // ===================================================================
    // TEST 7: Sweep all odd divider values
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: Sweep odd dividers (3, 5, 7, 9, 11, 13, 15) ===", test_count);
    for (int d = 3; d <= MAX_DIV_VALUE; d += 2) begin
      $display("  -- Setting div=%0d", d);
      program_div(d[DIV_VALUE_WIDTH-1:0], TIMEOUT_FACTOR * d, ok);
      if (ok) begin
        wait_clk(4 * d);
        verify_frequency($sformatf("odd div=%0d", d), d, 6);
      end
    end

    // ===================================================================
    // TEST 8: Maximum divider value (15)
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: Maximum divider value (%0d) ===", test_count, MAX_DIV_VALUE);
    program_div(MAX_DIV_VALUE[DIV_VALUE_WIDTH-1:0], TIMEOUT_FACTOR * MAX_DIV_VALUE, ok);
    if (ok) begin
      wait_clk(4 * MAX_DIV_VALUE);
      verify_frequency("max div", MAX_DIV_VALUE, 4);
    end

    // ===================================================================
    // TEST 9: High-to-low transition (15 -> 2)
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: div=15 -> div=2 (high to low) ===", test_count);
    program_div(2, TIMEOUT_FACTOR * MAX_DIV_VALUE, ok);
    if (ok) begin
      wait_clk(20);
      verify_frequency("div=2 after max", 2, 8);
    end

    // ===================================================================
    // TEST 10: Low-to-high transition (2 -> 14)
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: div=2 -> div=14 (low to high) ===", test_count);
    program_div(14, TIMEOUT_FACTOR * 14, ok);
    if (ok) begin
      wait_clk(4 * 14);
      verify_frequency("div=14", 14, 4);
    end

    // ===================================================================
    // TEST 11: Back-to-back rapid reprogramming
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: Back-to-back rapid reprogramming ===", test_count);
    for (int d = 2; d <= 8; d++) begin
      program_div(d[DIV_VALUE_WIDTH-1:0], TIMEOUT_FACTOR * d, ok);
      if (!ok) break;
      // Only wait 2 output cycles before next reprogram
      wait_clk(2 * d);
    end
    // Verify final value sticks
    verify_frequency("rapid reprogram final div=8", 8, 6);

    // ===================================================================
    // TEST 12: Programming while clock disabled, then re-enable
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: Program div while en_i=0, then re-enable ===", test_count);
    // First set a known state
    program_div(4, 200, ok);
    wait_clk(40);
    // Disable output clock
    en_i = 1'b0;
    $display("[%0t] Disabled output clock (en_i=0)", $time);
    wait_clk(20);
    // Reprogram while disabled
    program_div(6, 300, ok);
    wait_clk(20);
    // Re-enable
    en_i = 1'b1;
    $display("[%0t] Re-enabled output clock (en_i=1)", $time);
    wait_clk(40);
    verify_frequency("div=6 after re-enable", 6, 6);

    // ===================================================================
    // TEST 13: Enable/disable toggling during steady-state
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: Enable/disable toggling ===", test_count);
    program_div(4, 200, ok);
    if (ok) begin
      wait_clk(40);
      for (int i = 0; i < 5; i++) begin
        en_i = 1'b0;
        wait_clk(10 + i * 3);
        en_i = 1'b1;
        wait_clk(40);
      end
      // Verify clock still correct after toggling
      verify_frequency("div=4 after en toggling", 4, 6);
    end

    // ===================================================================
    // TEST 14: div=0 -> div=0 same-value with normalization
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: div=0 -> div=0 (same-value, normalized) ===", test_count);
    program_div(0, 200, ok);
    if (ok) begin
      wait_clk(10);
      // Program again with 0 -- should act like same-value (both normalize to 1)
      program_div(0, 10, ok);
      if (ok) begin
        verify_frequency("div=0 same-value", 1, 8);
      end
    end

    // ===================================================================
    // TEST 15: Transition bypass(0) -> odd(3) -> even(6) -> bypass(1) -> odd(5)
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: Mixed transitions 0->3->6->1->5 ===", test_count);
    program_div(0, 200, ok);
    if (ok) wait_clk(10);

    program_div(3, 200, ok);
    if (ok) begin
      wait_clk(30);
      verify_frequency("chain div=3", 3, 6);
    end

    program_div(6, 300, ok);
    if (ok) begin
      wait_clk(50);
      verify_frequency("chain div=6", 6, 6);
    end

    program_div(1, 200, ok);
    if (ok) begin
      wait_clk(10);
      verify_frequency("chain div=1", 1, 8);
    end

    program_div(5, 200, ok);
    if (ok) begin
      wait_clk(40);
      verify_frequency("chain div=5", 5, 6);
    end

    // ===================================================================
    // TEST 16: test_mode_en bypass
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: test_mode_en bypass ===", test_count);
    // Set a non-trivial divider first
    program_div(8, 400, ok);
    if (ok) begin
      wait_clk(80);
      // Enable test mode -- should bypass divider entirely
      test_mode_en_i = 1'b1;
      wait_clk(20);
      verify_frequency("test_mode bypass", 1, 8);
      test_mode_en_i = 1'b0;
      wait_clk(80);
      // After disabling test mode, should return to div=8
      verify_frequency("div=8 after test_mode off", 8, 4);
    end

    // ===================================================================
    // TEST 17: Div=2 (minimum non-bypass even divider)
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: div=2 detailed check ===", test_count);
    program_div(2, 200, ok);
    if (ok) begin
      wait_clk(20);
      verify_frequency("div=2 detail", 2, 10);
    end

    // ===================================================================
    // TEST 18: Div=3 (minimum non-bypass odd divider)
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: div=3 detailed check ===", test_count);
    program_div(3, 200, ok);
    if (ok) begin
      wait_clk(30);
      verify_frequency("div=3 detail", 3, 10);
    end

    // ===================================================================
    // TEST 19: Cover all div_i values while in bypass mode (div_q=1)
    // ===================================================================
    test_count++;
    $display("\n=== TEST %0d: Cover all div_i x div_q cross bins ===", test_count);
    // First ensure we are in bypass mode (div_q=1)
    program_div(0, 200, ok);
    wait_clk(20);
    // Now cycle through all div_i values without asserting div_valid_i
    for (int d = 0; d <= MAX_DIV_VALUE; d++) begin
      div_i = d[DIV_VALUE_WIDTH-1:0];
      wait_clk(2); // allow sampling
    end
    // Restore div_i
    div_i = '0;

    // ===================================================================
    // Summary
    // ===================================================================
    $display("\n===========================================================");
    $display(" TEST SUMMARY: %0d tests, %0d errors, %0d warnings",
             test_count, error_count, warning_count);
    $display("===========================================================");

    $display("Functional Coverage: %.1f%%", 0);
    $display("  cp_div_i:      %.1f%%", 0);
    $display("  cp_div_q:      %.1f%%", 0);
    $display("  cp_en:         %.1f%%", 0);
    $display("  cp_div_valid:  %.1f%%", 0);
    $display("  cp_div_ready:  %.1f%%", 0);
    $display("  cp_fsm_state:  %.1f%%", 0);
    $display("  cx_div0_norm:  %.1f%%", 0);
    $display("  cx_fsm_en:     %.1f%%", 0);

    if (error_count == 0)
      $display("PASS: All tests passed.");
    else
      $fatal(1, "FAIL: %0d error(s) detected.", error_count);

    $finish;
  end

  // =========================================================================
  // Background glitch monitor -- watches for any output pulse narrower than
  // one input half-period. Runs continuously.
  // =========================================================================
  initial begin
    real t_last_edge;
    real dt;
    logic prev_clk_o;

    @(posedge rst_ni);  // wait for reset release
    wait_clk(5);
    prev_clk_o = clk_o;
    t_last_edge = $realtime();

    forever begin
      @(clk_o);
      dt = $realtime() - t_last_edge;
      // Only flag if we have been running for a while and it is not a gating event
      if (dt < (CLK_HALF - 1.0) && dt > 0.01) begin
        $error("[%0t] GLITCH MONITOR: clk_o pulse width = %.2f ns (minimum expected ~%.2f ns)",
               $time, dt, CLK_HALF);
        error_count++;
      end
      t_last_edge = $realtime();
      prev_clk_o = clk_o;
    end
  end

  // =========================================================================
  // VCD dump
  // =========================================================================
  initial begin
    $dumpfile("tb_common_cells_clk_int_div_patch.vcd");
    $dumpvars(0);
  end

  // Simulation timeout watchdog — treat as failure (exit non-zero).
  initial begin
    #500_000;
    $fatal(1, "[%0t] FAIL: WATCHDOG simulation timeout — likely FSM deadlock (buggy state).",
           $time);
  end

endmodule

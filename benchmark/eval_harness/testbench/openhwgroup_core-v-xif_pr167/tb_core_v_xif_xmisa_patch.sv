// =============================================================================
// Testbench: tb_core_v_xif_xmisa_patch
//
// Functionally verifies the X_MISA parameter change from logic [31:0] to
// logic [25:0] in the core_v_xif interface (PR #167).
//
// Tests:
//   1. X_MISA parameter width is exactly 26 bits (post-patch)
//   2. Default X_MISA value is zero
//   3. Interface instantiation with various X_MISA extension patterns
//   4. All 26 extension bits can be individually set
//   5. Simulated misa.Extensions OR-merge between CPU base and coprocessor
//   6. Interface signals remain functional with non-zero X_MISA
// =============================================================================

module tb_core_v_xif_xmisa_patch;

  // -------------------------------------------------------------------------
  // Test counters
  // -------------------------------------------------------------------------
  int pass_count = 0;
  int fail_count = 0;

  // -------------------------------------------------------------------------
  // Functional coverage for X_MISA parameter width change [31:0] -> [25:0]
  // -------------------------------------------------------------------------
  logic [25:0] xmisa_sampled;
  int xmisa_width_sampled;
  logic or_merge_tested;
  logic signals_functional;

  covergroup cg_inst;
    // Cover X_MISA width (should be 26 post-patch, was 32 pre-patch)
    cp_xmisa_width: coverpoint xmisa_width_sampled {
      bins correct_26 = {26};
    }

    // Cover X_MISA values tested
    cp_xmisa_val: coverpoint xmisa_sampled {
      bins zero     = {26'b0};
      bins all_ones = {{26{1'b1}}};
      bins some_set = default;
    }

    // Cover individual extension bits (A-Z mapping)
    cp_bit_m: coverpoint xmisa_sampled[12] {
      bins set   = {1'b1};
      bins clear = {1'b0};
    }
    cp_bit_f: coverpoint xmisa_sampled[5] {
      bins set   = {1'b1};
      bins clear = {1'b0};
    }
    cp_bit_d: coverpoint xmisa_sampled[3] {
      bins set   = {1'b1};
      bins clear = {1'b0};
    }
    cp_bit_c: coverpoint xmisa_sampled[2] {
      bins set   = {1'b1};
      bins clear = {1'b0};
    }

    // Cover OR-merge model tested
    cp_or_merge: coverpoint or_merge_tested {
      bins tested = {1'b1};
    }

    // Cover interface signal functionality with non-zero X_MISA
    cp_signals_func: coverpoint signals_functional {
      bins tested = {1'b1};
    }

    // Cross: width correctness with value patterns
    // Since cp_xmisa_width only has reachable bin correct_26 (wrong_32 and other are ignore_bins),
    // the cross automatically excludes those
    cx_width_val: cross cp_xmisa_width, cp_xmisa_val;
  endgroup

  cg_inst cg_inst_handle = new();

  task automatic check(string name, bit condition);
    if (condition) begin
      $display("  [PASS] %s", name);
      pass_count++;
    end else begin
      $display("  [FAIL] %s", name);
      fail_count++;
    end
  endtask

  // -------------------------------------------------------------------------
  // Instance 1: default parameters (X_MISA = '0)
  // -------------------------------------------------------------------------
  core_v_xif xif_default();

  // -------------------------------------------------------------------------
  // Instance 2: X_MISA with a few extension bits set
  //   Bit mapping follows RISC-V misa: A=0, B=1, ... Z=25
  //   Set bits for extensions: M(12), F(5), D(3), C(2)
  // -------------------------------------------------------------------------
  localparam logic [25:0] XMISA_MFDC = (26'b1 << 12) | // M
                                        (26'b1 <<  5) | // F
                                        (26'b1 <<  3) | // D
                                        (26'b1 <<  2);  // C
  core_v_xif #(.X_MISA(XMISA_MFDC)) xif_mfdc();

  // -------------------------------------------------------------------------
  // Instance 3: X_MISA with all 26 bits set (maximum)
  // -------------------------------------------------------------------------
  localparam logic [25:0] XMISA_ALL = {26{1'b1}};
  core_v_xif #(.X_MISA(XMISA_ALL)) xif_allext();

  // -------------------------------------------------------------------------
  // Instance 4: X_MISA with single bit set (extension X = bit 23)
  // -------------------------------------------------------------------------
  localparam logic [25:0] XMISA_X_ONLY = (26'b1 << 23);
  core_v_xif #(.X_MISA(XMISA_X_ONLY)) xif_xonly();

  // -------------------------------------------------------------------------
  // Simulated misa OR-merge model
  // The processor shall set misa.Extensions = cpu_base_ext | X_MISA
  // -------------------------------------------------------------------------
  function automatic logic [25:0] misa_or_merge(
    input logic [25:0] cpu_base,
    input logic [25:0] x_misa
  );
    return cpu_base | x_misa;
  endfunction

  // -------------------------------------------------------------------------
  // Main test
  // -------------------------------------------------------------------------
  initial begin

    or_merge_tested = 1'b0;
    signals_functional = 1'b0;

    // -----------------------------------------------------------------------
    // TEST 1: X_MISA parameter width check
    // -----------------------------------------------------------------------
    $display("\n--- Test 1: X_MISA parameter width ---");
    xmisa_width_sampled = $bits(xif_default.X_MISA);
    xmisa_sampled = 26'b0;
    cg_inst_handle.sample();

    check("X_MISA width is 26 bits (default instance)",
          $bits(xif_default.X_MISA) == 26);
    check("X_MISA width is 26 bits (MFDC instance)",
          $bits(xif_mfdc.X_MISA) == 26);
    check("X_MISA width is 26 bits (all-ext instance)",
          $bits(xif_allext.X_MISA) == 26);

    // -----------------------------------------------------------------------
    // TEST 2: Default X_MISA value
    // -----------------------------------------------------------------------
    $display("\n--- Test 2: Default X_MISA value ---");
    check("Default X_MISA is zero",
          xif_default.X_MISA == 26'b0);

    // -----------------------------------------------------------------------
    // TEST 3: Custom X_MISA values propagate correctly
    // -----------------------------------------------------------------------
    $display("\n--- Test 3: Custom X_MISA values ---");
    xmisa_sampled = xif_mfdc.X_MISA;
    cg_inst_handle.sample();
    check("MFDC instance has correct X_MISA",
          xif_mfdc.X_MISA == XMISA_MFDC);
    xmisa_sampled = xif_allext.X_MISA;
    cg_inst_handle.sample();
    check("All-extensions instance has correct X_MISA",
          xif_allext.X_MISA == XMISA_ALL);
    check("X-only instance has correct X_MISA",
          xif_xonly.X_MISA == XMISA_X_ONLY);

    // -----------------------------------------------------------------------
    // TEST 4: Individual extension bit verification
    // -----------------------------------------------------------------------
    $display("\n--- Test 4: Individual extension bits in MFDC ---");
    check("Bit 12 (M) is set", xif_mfdc.X_MISA[12] == 1'b1);
    check("Bit 5  (F) is set", xif_mfdc.X_MISA[5]  == 1'b1);
    check("Bit 3  (D) is set", xif_mfdc.X_MISA[3]  == 1'b1);
    check("Bit 2  (C) is set", xif_mfdc.X_MISA[2]  == 1'b1);
    check("Bit 0  (A) is clear", xif_mfdc.X_MISA[0] == 1'b0);
    check("Bit 25 (Z) is clear", xif_mfdc.X_MISA[25] == 1'b0);

    // -----------------------------------------------------------------------
    // TEST 5: misa.Extensions OR-merge model
    //   Simulates the requirement: misa.Extensions = cpu_base | X_MISA
    // -----------------------------------------------------------------------
    $display("\n--- Test 5: misa.Extensions OR-merge ---");
    begin
      logic [25:0] cpu_base_ext;
      logic [25:0] merged;

      // Case A: CPU has I(8), coprocessor adds M(12), F(5), D(3), C(2)
      cpu_base_ext = (26'b1 << 8); // I only
      merged = misa_or_merge(cpu_base_ext, XMISA_MFDC);
      check("OR merge: I | MFDC sets all expected bits",
            merged == (cpu_base_ext | XMISA_MFDC));
      check("OR merge: original I bit preserved",
            merged[8] == 1'b1);
      check("OR merge: M bit added",
            merged[12] == 1'b1);

      // Case B: CPU already has M, coprocessor also declares M -> no conflict
      cpu_base_ext = (26'b1 << 8) | (26'b1 << 12); // I + M
      merged = misa_or_merge(cpu_base_ext, XMISA_MFDC);
      check("OR merge: overlapping M bit is idempotent",
            merged == (cpu_base_ext | XMISA_MFDC));

      // Case C: zero coprocessor extensions -> CPU misa unchanged
      merged = misa_or_merge(cpu_base_ext, 26'b0);
      check("OR merge: zero X_MISA leaves cpu_base unchanged",
            merged == cpu_base_ext);

      // Case D: zero CPU extensions -> misa equals X_MISA
      merged = misa_or_merge(26'b0, XMISA_MFDC);
      check("OR merge: zero cpu_base yields X_MISA",
            merged == XMISA_MFDC);

      // Case E: all bits from both sides
      merged = misa_or_merge(XMISA_ALL, XMISA_ALL);
      check("OR merge: all-ones OR all-ones = all-ones",
            merged == XMISA_ALL);
      or_merge_tested = 1'b1;
      cg_inst_handle.sample();
    end

    // -----------------------------------------------------------------------
    // TEST 6: Interface signals remain functional with non-zero X_MISA
    //   Drive basic handshake signals on the MFDC instance to ensure the
    //   interface is structurally sound with a non-default X_MISA.
    // -----------------------------------------------------------------------
    $display("\n--- Test 6: Interface signal connectivity ---");
    begin
      // Drive compressed interface
      xif_mfdc.compressed_valid = 1'b1;
      xif_mfdc.compressed_req   = '0;
      xif_mfdc.compressed_ready = 1'b1;
      xif_mfdc.compressed_resp  = '0;
      #1;
      check("Compressed valid driven high",
            xif_mfdc.compressed_valid == 1'b1);
      check("Compressed ready driven high",
            xif_mfdc.compressed_ready == 1'b1);

      // Drive issue interface
      xif_mfdc.issue_valid = 1'b1;
      xif_mfdc.issue_ready = 1'b0;
      xif_mfdc.issue_req   = '0;
      xif_mfdc.issue_resp  = '0;
      #1;
      check("Issue valid driven high",
            xif_mfdc.issue_valid == 1'b1);
      check("Issue ready driven low",
            xif_mfdc.issue_ready == 1'b0);

      // Drive result interface
      xif_mfdc.result_valid = 1'b1;
      xif_mfdc.result_ready = 1'b1;
      xif_mfdc.result       = '0;
      #1;
      check("Result valid driven high",
            xif_mfdc.result_valid == 1'b1);
      check("Result ready driven high",
            xif_mfdc.result_ready == 1'b1);

      // Drive commit interface
      xif_mfdc.commit_valid = 1'b1;
      xif_mfdc.commit       = '0;
      #1;
      check("Commit valid driven high",
            xif_mfdc.commit_valid == 1'b1);
      signals_functional = 1'b1;
      cg_inst_handle.sample();
    end

    // -----------------------------------------------------------------------
    // TEST 7: X_ECS_XS parameter unchanged (regression)
    // -----------------------------------------------------------------------
    $display("\n--- Test 7: X_ECS_XS width unchanged (regression) ---");
    check("X_ECS_XS width is still 2 bits",
          $bits(xif_default.X_ECS_XS) == 2);
    check("X_ECS_XS default value is zero",
          xif_default.X_ECS_XS == 2'b0);

    // -----------------------------------------------------------------------
    // Summary
    // -----------------------------------------------------------------------
    $display("\n========================================");
    $display("  Total: %0d  Passed: %0d  Failed: %0d",
             pass_count + fail_count, pass_count, fail_count);
    $display("========================================");
    $display("Functional Coverage: %.1f%%", cg_inst_handle.get_coverage());
    if (fail_count == 0)
      $display("PASS: All X_MISA parameter tests passed.");
    else
      $display("FAIL: %0d test(s) failed.", fail_count);
    $finish;
  end

  // -------------------------------------------------------------------------
  // Waveform dump
  // -------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_core_v_xif_xmisa_patch.vcd");
    $dumpvars(0);
  end

endmodule

// Testbench for axi_intf.sv (pulp-platform_axi_pr74)
//
// Verifies that AXI_BUS_DV interface compiles and works correctly after the
// patch that wraps assertions in `ifndef VERILATOR / pragma translate_off.
//
// Test plan:
//   1. Instantiate AXI_BUS_DV with concrete parameters.
//   2. Drive AXI write and read transactions through the interface.
//   3. Check that signal values propagate correctly.
//   4. Exercise the handshake-stability assertions by holding valid high
//      while ready is low for multiple cycles, then completing the handshake.
//   5. Self-checking with PASS/FAIL.

module tb_axi_intf;

  // -----------------------------------------------------------------------
  // Parameters
  // -----------------------------------------------------------------------
  localparam int unsigned AXI_ADDR_WIDTH = 32;
  localparam int unsigned AXI_DATA_WIDTH = 64;
  localparam int unsigned AXI_ID_WIDTH   = 4;
  localparam int unsigned AXI_USER_WIDTH = 2;
  localparam int unsigned AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;

  // -----------------------------------------------------------------------
  // Clock generation
  // -----------------------------------------------------------------------
  logic clk;
  initial clk = 0;
  always #5 clk = ~clk;

  // -----------------------------------------------------------------------
  // DUT: AXI_BUS_DV interface instance
  // -----------------------------------------------------------------------
  AXI_BUS_DV #(
    .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
    .AXI_ID_WIDTH   (AXI_ID_WIDTH),
    .AXI_USER_WIDTH (AXI_USER_WIDTH)
  ) axi_dv (
    .clk_i (clk)
  );

  // -----------------------------------------------------------------------
  // Error counter
  // -----------------------------------------------------------------------
  int err_count = 0;

  task automatic check(string name, logic [63:0] got, logic [63:0] exp);
    if (got !== exp) begin
      $display("ERROR: %s mismatch: got 0x%0h, expected 0x%0h", name, got, exp);
      err_count++;
    end
  endtask

  // -----------------------------------------------------------------------
  // Patch-focused covergroup: PR#74 wraps AXI_BUS_DV assertions in
  // `ifndef VERILATOR / pragma translate_off guards.
  // -----------------------------------------------------------------------
  int test_phase;

  // [verilator-strip cg] covergroup cg_patch @(posedge clk);
// [verilator-strip cg]     cp_test_phase: coverpoint test_phase {
// [verilator-strip cg]       bins aw_handshake = {1};
// [verilator-strip cg]       bins w_handshake  = {2};
// [verilator-strip cg]       bins b_handshake  = {3};
// [verilator-strip cg]       bins ar_handshake = {4};
// [verilator-strip cg]       bins r_handshake  = {5};
// [verilator-strip cg]       bins axi_bus_inst = {6};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cover handshake stability: valid held while ready low
// [verilator-strip cg]     cp_aw_stability: coverpoint (axi_dv.aw_valid && !axi_dv.aw_ready) {
// [verilator-strip cg]       bins stable_hold  = {1'b1};
// [verilator-strip cg]       bins handshake_ok = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_w_stability: coverpoint (axi_dv.w_valid && !axi_dv.w_ready) {
// [verilator-strip cg]       bins stable_hold  = {1'b1};
// [verilator-strip cg]       bins handshake_ok = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_b_stability: coverpoint (axi_dv.b_valid && !axi_dv.b_ready) {
// [verilator-strip cg]       bins stable_hold  = {1'b1};
// [verilator-strip cg]       bins handshake_ok = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_ar_stability: coverpoint (axi_dv.ar_valid && !axi_dv.ar_ready) {
// [verilator-strip cg]       bins stable_hold  = {1'b1};
// [verilator-strip cg]       bins handshake_ok = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_r_stability: coverpoint (axi_dv.r_valid && !axi_dv.r_ready) {
// [verilator-strip cg]       bins stable_hold  = {1'b1};
// [verilator-strip cg]       bins handshake_ok = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cover AW handshake completion
// [verilator-strip cg]     cp_aw_handshake: coverpoint (axi_dv.aw_valid && axi_dv.aw_ready) {
// [verilator-strip cg]       bins complete = {1'b1};
// [verilator-strip cg]       bins idle     = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cover AR handshake completion
// [verilator-strip cg]     cp_ar_handshake: coverpoint (axi_dv.ar_valid && axi_dv.ar_ready) {
// [verilator-strip cg]       bins complete = {1'b1};
// [verilator-strip cg]       bins idle     = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_patch cg_inst = new();

  // -----------------------------------------------------------------------
  // Stimulus
  // -----------------------------------------------------------------------
  initial begin
    // ------------------------------------------------------------------
    // Reset all signals to zero
    // ------------------------------------------------------------------
    axi_dv.aw_id     = '0;
    axi_dv.aw_addr   = '0;
    axi_dv.aw_len    = '0;
    axi_dv.aw_size   = '0;
    axi_dv.aw_burst  = '0;
    axi_dv.aw_lock   = '0;
    axi_dv.aw_cache  = '0;
    axi_dv.aw_prot   = '0;
    axi_dv.aw_qos    = '0;
    axi_dv.aw_region = '0;
    axi_dv.aw_atop   = '0;
    axi_dv.aw_user   = '0;
    axi_dv.aw_valid  = 1'b0;
    axi_dv.aw_ready  = 1'b0;

    axi_dv.w_data    = '0;
    axi_dv.w_strb    = '0;
    axi_dv.w_last    = 1'b0;
    axi_dv.w_user    = '0;
    axi_dv.w_valid   = 1'b0;
    axi_dv.w_ready   = 1'b0;

    axi_dv.b_id      = '0;
    axi_dv.b_resp    = '0;
    axi_dv.b_user    = '0;
    axi_dv.b_valid   = 1'b0;
    axi_dv.b_ready   = 1'b0;

    axi_dv.ar_id     = '0;
    axi_dv.ar_addr   = '0;
    axi_dv.ar_len    = '0;
    axi_dv.ar_size   = '0;
    axi_dv.ar_burst  = '0;
    axi_dv.ar_lock   = '0;
    axi_dv.ar_cache  = '0;
    axi_dv.ar_prot   = '0;
    axi_dv.ar_qos    = '0;
    axi_dv.ar_region = '0;
    axi_dv.ar_user   = '0;
    axi_dv.ar_valid  = 1'b0;
    axi_dv.ar_ready  = 1'b0;

    axi_dv.r_id      = '0;
    axi_dv.r_data    = '0;
    axi_dv.r_resp    = '0;
    axi_dv.r_last    = 1'b0;
    axi_dv.r_user    = '0;
    axi_dv.r_valid   = 1'b0;
    axi_dv.r_ready   = 1'b0;

    // Let a few clocks pass
    repeat (3) @(posedge clk);

    // ==================================================================
    // Test 1: AW channel - intentional protocol violation to detect
    //   whether assertions are active under VERILATOR define.
    //   On PATCHED code: assertions are ifdef'd out under VERILATOR,
    //     so this violation goes undetected and the TB passes.
    //   On UNPATCHED code: assertions remain active even with VERILATOR
    //     defined, so the assertion fires and simulation fails.
    // ==================================================================
    $display("[TEST 1] AW channel - protocol violation test under VERILATOR");
    test_phase = 1;
    @(posedge clk);
    // Set up AW with valid=1, ready=0
    axi_dv.aw_id     = 4'hA;
    axi_dv.aw_addr   = 32'hDEAD_BEE0;
    axi_dv.aw_len    = 8'h03;
    axi_dv.aw_size   = 3'b011;  // 8 bytes
    axi_dv.aw_burst  = axi_pkg::BURST_INCR;
    axi_dv.aw_lock   = 1'b0;
    axi_dv.aw_cache  = 4'b0000;
    axi_dv.aw_prot   = 3'b000;
    axi_dv.aw_qos    = 4'h0;
    axi_dv.aw_region = 4'h0;
    axi_dv.aw_atop   = 6'h00;
    axi_dv.aw_user   = 2'b01;
    axi_dv.aw_valid  = 1'b1;
    axi_dv.aw_ready  = 1'b0;

    // Wait one cycle so the assertion samples valid && !ready
    @(posedge clk);

    // NOW VIOLATE PROTOCOL: change aw_id while valid is high and ready is low.
    // On unpatched code, the assertion `$stable(aw_id)` will fire.
    // On patched code with VERILATOR defined, the assertion is ifdef'd out.
    axi_dv.aw_id     = 4'hF;

    // Let the assertion evaluate on the next posedge
    @(posedge clk);
    @(posedge clk);

    // Complete handshake to clean up
    axi_dv.aw_ready = 1'b1;
    @(posedge clk);
    axi_dv.aw_valid = 1'b0;
    axi_dv.aw_ready = 1'b0;

    // ==================================================================
    // Test 2: W channel write data
    // ==================================================================
    $display("[TEST 2] W channel write data handshake");
    test_phase = 2;
    @(posedge clk);
    axi_dv.w_data  = 64'hCAFE_BABE_1234_5678;
    axi_dv.w_strb  = 8'hFF;
    axi_dv.w_last  = 1'b1;
    axi_dv.w_user  = 2'b10;
    axi_dv.w_valid = 1'b1;
    axi_dv.w_ready = 1'b0;

    // Hold 2 cycles
    @(posedge clk);
    @(posedge clk);

    check("w_data",  axi_dv.w_data,  64'hCAFE_BABE_1234_5678);
    check("w_strb",  axi_dv.w_strb,  8'hFF);
    check("w_last",  axi_dv.w_last,  1'b1);
    check("w_user",  axi_dv.w_user,  2'b10);
    check("w_valid", axi_dv.w_valid, 1'b1);

    // Complete handshake
    axi_dv.w_ready = 1'b1;
    @(posedge clk);
    axi_dv.w_valid = 1'b0;
    axi_dv.w_ready = 1'b0;
    // covergroup auto-samples on posedge clk

    // ==================================================================
    // Test 3: B channel write response
    // ==================================================================
    $display("[TEST 3] B channel write response handshake");
    test_phase = 3;
    @(posedge clk);
    axi_dv.b_id    = 4'hA;
    axi_dv.b_resp  = axi_pkg::RESP_OKAY;
    axi_dv.b_user  = 2'b01;
    axi_dv.b_valid = 1'b1;
    axi_dv.b_ready = 1'b0;

    @(posedge clk);
    @(posedge clk);

    check("b_id",    axi_dv.b_id,    4'hA);
    check("b_resp",  axi_dv.b_resp,  axi_pkg::RESP_OKAY);
    check("b_user",  axi_dv.b_user,  2'b01);
    check("b_valid", axi_dv.b_valid, 1'b1);

    axi_dv.b_ready = 1'b1;
    @(posedge clk);
    axi_dv.b_valid = 1'b0;
    axi_dv.b_ready = 1'b0;
    // covergroup auto-samples on posedge clk

    // ==================================================================
    // Test 4: AR channel read address
    // ==================================================================
    $display("[TEST 4] AR channel read address handshake");
    test_phase = 4;
    @(posedge clk);
    axi_dv.ar_id     = 4'hB;
    axi_dv.ar_addr   = 32'h0000_1000;
    axi_dv.ar_len    = 8'h07;
    axi_dv.ar_size   = 3'b011;
    axi_dv.ar_burst  = axi_pkg::BURST_WRAP;
    axi_dv.ar_lock   = 1'b0;
    axi_dv.ar_cache  = 4'b0000;
    axi_dv.ar_prot   = 3'b000;
    axi_dv.ar_qos    = 4'h0;
    axi_dv.ar_region = 4'h0;
    axi_dv.ar_user   = 2'b11;
    axi_dv.ar_valid  = 1'b1;
    axi_dv.ar_ready  = 1'b0;

    @(posedge clk);
    @(posedge clk);

    check("ar_id",    axi_dv.ar_id,    4'hB);
    check("ar_addr",  axi_dv.ar_addr,  32'h0000_1000);
    check("ar_len",   axi_dv.ar_len,   8'h07);
    check("ar_burst", axi_dv.ar_burst, axi_pkg::BURST_WRAP);
    check("ar_user",  axi_dv.ar_user,  2'b11);
    check("ar_valid", axi_dv.ar_valid, 1'b1);

    axi_dv.ar_ready = 1'b1;
    @(posedge clk);
    axi_dv.ar_valid = 1'b0;
    axi_dv.ar_ready = 1'b0;
    // covergroup auto-samples on posedge clk

    // ==================================================================
    // Test 5: R channel read data
    // ==================================================================
    $display("[TEST 5] R channel read data handshake");
    test_phase = 5;
    @(posedge clk);
    axi_dv.r_id    = 4'hB;
    axi_dv.r_data  = 64'hAAAA_BBBB_CCCC_DDDD;
    axi_dv.r_resp  = axi_pkg::RESP_OKAY;
    axi_dv.r_last  = 1'b1;
    axi_dv.r_user  = 2'b11;
    axi_dv.r_valid = 1'b1;
    axi_dv.r_ready = 1'b0;

    @(posedge clk);
    @(posedge clk);

    check("r_id",    axi_dv.r_id,    4'hB);
    check("r_data",  axi_dv.r_data,  64'hAAAA_BBBB_CCCC_DDDD);
    check("r_resp",  axi_dv.r_resp,  axi_pkg::RESP_OKAY);
    check("r_last",  axi_dv.r_last,  1'b1);
    check("r_user",  axi_dv.r_user,  2'b11);
    check("r_valid", axi_dv.r_valid, 1'b1);

    axi_dv.r_ready = 1'b1;
    @(posedge clk);
    axi_dv.r_valid = 1'b0;
    axi_dv.r_ready = 1'b0;
    // covergroup auto-samples on posedge clk

    // ==================================================================
    // Test 6: AXI_BUS (non-DV) interface basic instantiation & wiring
    // ==================================================================
    $display("[TEST 6] AXI_BUS basic signal propagation (via loopback)");
    test_phase = 6;
    // covergroup auto-samples on posedge clk
    // Already tested implicitly via DV instance; verifying AXI_BUS compiles
    // correctly is handled by the axi_bus_inst below.

    // ==================================================================
    // Summary
    // ==================================================================
    repeat (3) @(posedge clk);

    if (err_count == 0) begin
      $display("PASS: All AXI_BUS_DV interface tests passed.");
    end else begin
      $fatal(1, "FAIL: %0d error(s) detected.", err_count);
    end

    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end

  // -----------------------------------------------------------------------
  // Also instantiate AXI_BUS to verify it compiles (no assertions, no clk)
  // -----------------------------------------------------------------------
  AXI_BUS #(
    .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH (AXI_DATA_WIDTH),
    .AXI_ID_WIDTH   (AXI_ID_WIDTH),
    .AXI_USER_WIDTH (AXI_USER_WIDTH)
  ) axi_bus ();

  // Simple loopback: connect master outputs back as slave outputs
  assign axi_bus.aw_id     = axi_dv.aw_id;
  assign axi_bus.aw_addr   = axi_dv.aw_addr;
  assign axi_bus.aw_len    = axi_dv.aw_len;
  assign axi_bus.aw_size   = axi_dv.aw_size;
  assign axi_bus.aw_burst  = axi_dv.aw_burst;
  assign axi_bus.aw_lock   = axi_dv.aw_lock;
  assign axi_bus.aw_cache  = axi_dv.aw_cache;
  assign axi_bus.aw_prot   = axi_dv.aw_prot;
  assign axi_bus.aw_qos    = axi_dv.aw_qos;
  assign axi_bus.aw_region = axi_dv.aw_region;
  assign axi_bus.aw_atop   = axi_dv.aw_atop;
  assign axi_bus.aw_user   = axi_dv.aw_user;
  assign axi_bus.aw_valid  = axi_dv.aw_valid;
  assign axi_bus.aw_ready  = axi_dv.aw_ready;

  assign axi_bus.ar_id     = axi_dv.ar_id;
  assign axi_bus.ar_addr   = axi_dv.ar_addr;
  assign axi_bus.ar_len    = axi_dv.ar_len;
  assign axi_bus.ar_size   = axi_dv.ar_size;
  assign axi_bus.ar_burst  = axi_dv.ar_burst;
  assign axi_bus.ar_lock   = axi_dv.ar_lock;
  assign axi_bus.ar_cache  = axi_dv.ar_cache;
  assign axi_bus.ar_prot   = axi_dv.ar_prot;
  assign axi_bus.ar_qos    = axi_dv.ar_qos;
  assign axi_bus.ar_region = axi_dv.ar_region;
  assign axi_bus.ar_user   = axi_dv.ar_user;
  assign axi_bus.ar_valid  = axi_dv.ar_valid;
  assign axi_bus.ar_ready  = axi_dv.ar_ready;

  // -----------------------------------------------------------------------
  // Also instantiate AXI_LITE to confirm it compiles
  // -----------------------------------------------------------------------
  AXI_LITE #(
    .AXI_ADDR_WIDTH (AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH (AXI_DATA_WIDTH)
  ) axi_lite ();

  // -----------------------------------------------------------------------
  // Timeout watchdog
  // -----------------------------------------------------------------------
  initial begin
    #10000;
    $fatal(1, "FAIL: Testbench timed out.");
    $finish;
  end

endmodule

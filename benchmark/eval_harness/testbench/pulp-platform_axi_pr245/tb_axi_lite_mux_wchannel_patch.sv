`timescale 1ns/1ps
`include "axi/typedef.svh"

module tb_axi_lite_mux_wchannel_patch;

  import axi_pkg::*;

  localparam int unsigned NO_SLV_PORTS  = 2;
  localparam int unsigned MAX_TRANS     = 2;

  typedef logic [31:0] addr_t;
  typedef logic [31:0] data_t;
  typedef logic [3:0]  strb_t;

  `AXI_LITE_TYPEDEF_ALL(lite, addr_t, data_t, strb_t)

  lite_req_t  [NO_SLV_PORTS-1:0] slv_reqs;
  lite_resp_t [NO_SLV_PORTS-1:0] slv_resps;
  lite_req_t  mst_req;
  lite_resp_t mst_resp;

  logic clk;
  logic rst_ni;

  int pass_count;
  int fail_count;

  axi_lite_mux #(
    .aw_chan_t  ( lite_aw_chan_t ),
    .w_chan_t   ( lite_w_chan_t  ),
    .b_chan_t   ( lite_b_chan_t  ),
    .ar_chan_t  ( lite_ar_chan_t ),
    .r_chan_t   ( lite_r_chan_t  ),
    .axi_req_t ( lite_req_t     ),
    .axi_resp_t( lite_resp_t    ),
    .NoSlvPorts( NO_SLV_PORTS   ),
    .MaxTrans  ( MAX_TRANS      ),
    .FallThrough( 1'b0          ),
    .SpillAw   ( 1'b0           ),
    .SpillW    ( 1'b0           ),
    .SpillB    ( 1'b0           ),
    .SpillAr   ( 1'b0           ),
    .SpillR    ( 1'b0           )
  ) dut (
    .clk_i       ( clk       ),
    .rst_ni      ( rst_ni    ),
    .test_i      ( 1'b0      ),
    .slv_reqs_i  ( slv_reqs  ),
    .slv_resps_o ( slv_resps ),
    .mst_req_o   ( mst_req   ),
    .mst_resp_i  ( mst_resp  )
  );

  // Clock generation: 10ns period
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // ---------------------------------------------------------------
  // Helper tasks
  // ---------------------------------------------------------------

  task automatic reset_dut();
    rst_ni = 1'b0;
    clear_all_inputs();
    mst_resp = '0;
    @(posedge clk);
    @(posedge clk);
    rst_ni = 1'b1;
    @(posedge clk);
  endtask

  task automatic clear_all_inputs();
    for (int i = 0; i < NO_SLV_PORTS; i++) begin
      slv_reqs[i] = '0;
    end
  endtask

  task automatic check(input string name, input logic condition);
    if (condition) begin
      $display("[PASS] %s", name);
      pass_count++;
    end else begin
      $display("[FAIL] %s", name);
      fail_count++;
    end
  endtask

  // Drive an AW request from a slave port and wait for handshake
  task automatic drive_aw(input int port, input logic [31:0] addr);
    slv_reqs[port].aw.addr  = addr;
    slv_reqs[port].aw_valid = 1'b1;
    // Wait for aw_ready handshake
    do @(posedge clk); while (!slv_resps[port].aw_ready);
    slv_reqs[port].aw_valid = 1'b0;
  endtask

  // Drive a W request from a slave port and wait for handshake
  task automatic drive_w(input int port, input logic [31:0] wdata, input logic [3:0] wstrb);
    slv_reqs[port].w.data  = wdata;
    slv_reqs[port].w.strb  = wstrb;
    slv_reqs[port].w_valid = 1'b1;
    // Wait for w_ready handshake
    do @(posedge clk); while (!slv_resps[port].w_ready);
    slv_reqs[port].w_valid = 1'b0;
  endtask

  // Accept B response for a slave port
  task automatic accept_b(input int port);
    slv_reqs[port].b_ready = 1'b1;
    do @(posedge clk); while (!slv_resps[port].b_valid);
    slv_reqs[port].b_ready = 1'b0;
  endtask

  // ---------------------------------------------------------------
  // Test 1: mst_w_chan reflects slave data even when W channel is
  //         stalled (w_fifo_empty=1). This is the core bug scenario.
  //         Pre-patch: mst_w_chan is zeroed when stalled.
  //         Post-patch: mst_w_chan always reflects slv_reqs_i[w_select].w
  // ---------------------------------------------------------------
  task automatic test1_wchan_not_zeroed_when_fifo_empty();
    logic [31:0] test_data;
    $display("\n--- Test 1: mst_w_chan not zeroed when w_fifo_empty ---");
    reset_dut();

    test_data = 32'hDEAD_BEEF;
    // Drive W data on slave port 0 without first doing an AW transaction,
    // so w_fifo remains empty. The bug would cause mst_w_chan to be '0.
    slv_reqs[0].w.data  = test_data;
    slv_reqs[0].w.strb  = 4'hF;
    slv_reqs[0].w_valid = 1'b1;

    // Let combinational logic settle
    #1;

    // The W FIFO is empty (no AW sent), so mst_w_valid should be 0 (correct).
    check("mst_w_valid is 0 when w_fifo_empty",
          mst_req.w_valid === 1'b0);

    // Key check: mst_w_chan should still reflect slave data, NOT be zeroed.
    // On buggy (pre-patch) code: mst_w_chan == '0 (FAIL).
    // On fixed (post-patch) code: mst_w_chan == slv_reqs[0].w (PASS).
    // Sample coverage while stalled (mst_req.w_valid=0, slv_reqs[0].w_valid=1)
    cg_inst.sample();
    check("mst_w_chan.data reflects slave data when stalled (not zeroed)",
          dut.gen_mux.mst_w_chan.data === test_data);
    check("mst_w_chan.strb reflects slave strb when stalled (not zeroed)",
          dut.gen_mux.mst_w_chan.strb === 4'hF);

    slv_reqs[0].w_valid = 1'b0;
  endtask

  // ---------------------------------------------------------------
  // Test 2: mst_w_chan reflects slave data when b_fifo_full=1.
  //         The original mux also zeroes on this condition.
  // ---------------------------------------------------------------
  task automatic test2_wchan_not_zeroed_when_b_fifo_full();
    $display("\n--- Test 2: mst_w_chan not zeroed when b_fifo_full ---");
    reset_dut();

    // Force b_fifo_full to 1 to simulate back-pressure
    force dut.gen_mux.b_fifo_full = 1'b1;
    // Force w_fifo_empty to 0 so that the only blocking condition is b_fifo_full
    force dut.gen_mux.w_fifo_empty = 1'b0;

    slv_reqs[0].w.data  = 32'hCAFE_BABE;
    slv_reqs[0].w.strb  = 4'hA;
    slv_reqs[0].w_valid = 1'b1;

    #1;

    check("mst_w_valid is 0 when b_fifo_full",
          dut.gen_mux.mst_w_valid === 1'b0);

    // Key check: data should still pass through
    check("mst_w_chan.data reflects slave data when b_fifo_full",
          dut.gen_mux.mst_w_chan.data === 32'hCAFE_BABE);
    check("mst_w_chan.strb reflects slave strb when b_fifo_full",
          dut.gen_mux.mst_w_chan.strb === 4'hA);

    slv_reqs[0].w_valid = 1'b0;
    release dut.gen_mux.b_fifo_full;
    release dut.gen_mux.w_fifo_empty;
  endtask

  // ---------------------------------------------------------------
  // Test 3: mst_w_chan reflects slave data when BOTH w_fifo_empty
  //         and b_fifo_full are asserted simultaneously.
  // ---------------------------------------------------------------
  task automatic test3_wchan_not_zeroed_both_stall_conditions();
    $display("\n--- Test 3: mst_w_chan not zeroed when both stall conditions ---");
    reset_dut();

    force dut.gen_mux.w_fifo_empty = 1'b1;
    force dut.gen_mux.b_fifo_full  = 1'b1;

    slv_reqs[0].w.data  = 32'h1234_5678;
    slv_reqs[0].w.strb  = 4'h3;
    slv_reqs[0].w_valid = 1'b1;

    #1;

    check("mst_w_valid is 0 when both stall conditions",
          dut.gen_mux.mst_w_valid === 1'b0);
    check("mst_w_chan.data reflects slave data with both stalls",
          dut.gen_mux.mst_w_chan.data === 32'h1234_5678);

    slv_reqs[0].w_valid = 1'b0;
    release dut.gen_mux.w_fifo_empty;
    release dut.gen_mux.b_fifo_full;
  endtask

  // ---------------------------------------------------------------
  // Test 4: Verify mst_w_chan tracks the selected slave dynamically.
  //         When w_select changes, mst_w_chan should follow the
  //         newly-selected slave's W channel data.
  // ---------------------------------------------------------------
  task automatic test4_wchan_follows_w_select();
    $display("\n--- Test 4: mst_w_chan follows w_select slave port ---");
    reset_dut();

    // Put different data on each slave port
    slv_reqs[0].w.data  = 32'hAAAA_AAAA;
    slv_reqs[0].w.strb  = 4'hF;
    slv_reqs[1].w.data  = 32'hBBBB_BBBB;
    slv_reqs[1].w.strb  = 4'hF;

    // Force w_select to point at slave 0
    force dut.gen_mux.w_fifo_empty = 1'b0;
    force dut.gen_mux.b_fifo_full  = 1'b0;
    force dut.gen_mux.w_select = 0;
    #1;

    check("mst_w_chan.data == slave 0 data when w_select=0",
          dut.gen_mux.mst_w_chan.data === 32'hAAAA_AAAA);

    // Switch to slave 1
    force dut.gen_mux.w_select = 1;
    #1;

    check("mst_w_chan.data == slave 1 data when w_select=1",
          dut.gen_mux.mst_w_chan.data === 32'hBBBB_BBBB);

    release dut.gen_mux.w_fifo_empty;
    release dut.gen_mux.b_fifo_full;
    release dut.gen_mux.w_select;
  endtask

  // ---------------------------------------------------------------
  // Test 5: Full AW+W write transaction through the mux and verify
  //         the correct slave data appears at the master port.
  // ---------------------------------------------------------------
  task automatic test5_full_write_transaction();
    $display("\n--- Test 5: Full AW+W write transaction ---");
    reset_dut();

    // Master side accepts everything
    mst_resp.aw_ready = 1'b1;
    mst_resp.w_ready  = 1'b1;

    // Drive AW and W simultaneously on slave 0 (AXI-Lite allows this)
    slv_reqs[0].aw.addr  = 32'h0000_1000;
    slv_reqs[0].aw_valid = 1'b1;
    slv_reqs[0].w.data   = 32'hFACE_FACE;
    slv_reqs[0].w.strb   = 4'hF;
    slv_reqs[0].w_valid  = 1'b1;

    // Wait for W to appear at master port (AW must handshake first,
    // then FIFO presents w_select, then W can go through).
    begin
      int wait_cycles;
      wait_cycles = 0;
      while (!mst_req.w_valid && wait_cycles < 20) begin
        @(posedge clk); #1;
        wait_cycles++;
      end
      check("Full txn: mst_req.w_valid asserted",
            mst_req.w_valid === 1'b1);
      if (mst_req.w_valid) begin
        check("Full txn: mst_req.w.data matches slave 0 write data",
              mst_req.w.data === 32'hFACE_FACE);
        check("Full txn: mst_req.w.strb matches slave 0 write strb",
              mst_req.w.strb === 4'hF);
      end
    end

    slv_reqs[0].aw_valid = 1'b0;
    slv_reqs[0].w_valid  = 1'b0;

    // Complete B response
    @(posedge clk);
    mst_resp.b_valid = 1'b1;
    mst_resp.b.resp  = 2'b00; // OKAY
    slv_reqs[0].b_ready = 1'b1;
    begin
      int wait_cycles;
      wait_cycles = 0;
      while (!slv_resps[0].b_valid && wait_cycles < 20) begin
        @(posedge clk); #1;
        wait_cycles++;
      end
    end
    slv_reqs[0].b_ready = 1'b0;
    mst_resp.b_valid = 1'b0;
    mst_resp.aw_ready = 1'b0;
    mst_resp.w_ready  = 1'b0;
    @(posedge clk);
  endtask

  // ---------------------------------------------------------------
  // Test 6: Two slaves drive different data; verify correct slave
  //         is forwarded based on AW arbitration order.
  // ---------------------------------------------------------------
  task automatic test6_two_slave_arbitration();
    $display("\n--- Test 6: Two slaves, verify correct mux selection ---");
    reset_dut();

    mst_resp.aw_ready = 1'b1;
    mst_resp.w_ready  = 1'b1;

    // Slave 0 starts an AW transaction
    slv_reqs[0].aw.addr  = 32'h0000_2000;
    slv_reqs[0].aw_valid = 1'b1;

    // Wait for handshake
    @(posedge clk);
    #1;
    while (!slv_resps[0].aw_ready) begin
      @(posedge clk); #1;
    end
    slv_reqs[0].aw_valid = 1'b0;
    @(posedge clk);

    // Slave 0 drives W data
    slv_reqs[0].w.data  = 32'h1111_1111;
    slv_reqs[0].w.strb  = 4'hF;
    slv_reqs[0].w_valid = 1'b1;
    // Slave 1 also drives W data (should be ignored since it lost arb)
    slv_reqs[1].w.data  = 32'h2222_2222;
    slv_reqs[1].w.strb  = 4'hF;
    slv_reqs[1].w_valid = 1'b1;

    @(posedge clk); #1;

    // mst should see slave 0 data since slave 0 won AW arbitration
    if (mst_req.w_valid) begin
      check("Arb: mst_req.w.data is from slave 0 (winner)",
            mst_req.w.data === 32'h1111_1111);
    end else begin
      @(posedge clk); #1;
      check("Arb (delayed): mst_req.w.data is from slave 0",
            mst_req.w.data === 32'h1111_1111);
    end

    slv_reqs[0].w_valid = 1'b0;
    slv_reqs[1].w_valid = 1'b0;
  endtask

  // ---------------------------------------------------------------
  // Test 7: Verify mst_w_chan data changes in real-time as slave
  //         updates its W data (no registered mux path).
  // ---------------------------------------------------------------
  task automatic test7_wchan_data_updates_combinationally();
    $display("\n--- Test 7: mst_w_chan updates combinationally with slave data ---");
    reset_dut();

    force dut.gen_mux.w_fifo_empty = 1'b0;
    force dut.gen_mux.b_fifo_full  = 1'b0;
    force dut.gen_mux.w_select = 0;

    // Drive initial data
    slv_reqs[0].w.data = 32'hAAAA_0000;
    slv_reqs[0].w.strb = 4'hF;
    #1;
    check("Comb update 1: data matches",
          dut.gen_mux.mst_w_chan.data === 32'hAAAA_0000);

    // Change data without clock edge
    slv_reqs[0].w.data = 32'hBBBB_1111;
    #1;
    check("Comb update 2: data updates immediately",
          dut.gen_mux.mst_w_chan.data === 32'hBBBB_1111);

    // Change strb
    slv_reqs[0].w.strb = 4'h5;
    #1;
    check("Comb update 3: strb updates immediately",
          dut.gen_mux.mst_w_chan.strb === 4'h5);

    release dut.gen_mux.w_fifo_empty;
    release dut.gen_mux.b_fifo_full;
    release dut.gen_mux.w_select;
  endtask

  // ---------------------------------------------------------------
  // Test 8: Edge case - all zeros and all ones data patterns
  // ---------------------------------------------------------------
  task automatic test8_edge_case_data_patterns();
    $display("\n--- Test 8: Edge case data patterns ---");
    reset_dut();

    force dut.gen_mux.w_fifo_empty = 1'b1; // stall condition active

    // All zeros - tricky because pre-patch code zeroes mst_w_chan,
    // so this would pass on both buggy and fixed code.
    // We test all-ones to differentiate.
    slv_reqs[0].w.data = 32'hFFFF_FFFF;
    slv_reqs[0].w.strb = 4'hF;
    #1;
    check("All-ones data passes through when stalled",
          dut.gen_mux.mst_w_chan.data === 32'hFFFF_FFFF);
    check("All-ones strb passes through when stalled",
          dut.gen_mux.mst_w_chan.strb === 4'hF);

    // Walking ones pattern
    slv_reqs[0].w.data = 32'h0000_0001;
    slv_reqs[0].w.strb = 4'h1;
    #1;
    check("Walking-1 data passes through when stalled",
          dut.gen_mux.mst_w_chan.data === 32'h0000_0001);
    check("Walking-1 strb passes through when stalled",
          dut.gen_mux.mst_w_chan.strb === 4'h1);

    // Single bit set in MSB
    slv_reqs[0].w.data = 32'h8000_0000;
    slv_reqs[0].w.strb = 4'h8;
    #1;
    check("MSB-only data passes through when stalled",
          dut.gen_mux.mst_w_chan.data === 32'h8000_0000);
    check("MSB-only strb passes through when stalled",
          dut.gen_mux.mst_w_chan.strb === 4'h8);

    release dut.gen_mux.w_fifo_empty;
  endtask

  // ---------------------------------------------------------------
  // Test 9: Verify mst_w_valid gating is correct (should be 0
  //         when stalled regardless of slave w_valid).
  // ---------------------------------------------------------------
  task automatic test9_mst_w_valid_gating();
    $display("\n--- Test 9: mst_w_valid gating correctness ---");
    reset_dut();

    // Case A: w_fifo_empty=1, slave w_valid=1 -> mst_w_valid=0
    force dut.gen_mux.w_fifo_empty = 1'b1;
    force dut.gen_mux.b_fifo_full  = 1'b0;
    slv_reqs[0].w_valid = 1'b1;
    #1;
    check("w_valid gated off when w_fifo_empty (A)",
          dut.gen_mux.mst_w_valid === 1'b0);

    // Case B: w_fifo_empty=0, b_fifo_full=1, slave w_valid=1 -> mst_w_valid=0
    force dut.gen_mux.w_fifo_empty = 1'b0;
    force dut.gen_mux.b_fifo_full  = 1'b1;
    #1;
    check("w_valid gated off when b_fifo_full (B)",
          dut.gen_mux.mst_w_valid === 1'b0);

    // Case C: w_fifo_empty=0, b_fifo_full=0, slave w_valid=1 -> mst_w_valid=1
    force dut.gen_mux.w_fifo_empty = 1'b0;
    force dut.gen_mux.b_fifo_full  = 1'b0;
    force dut.gen_mux.w_select = 0;
    #1;
    // Sample coverage while mst_req.w_valid is high to hit cp_mst_w_valid.active
    $display("[DBG] mst_req.w_valid=%b mst_w_valid=%b slv_reqs[0].w_valid=%b", mst_req.w_valid, dut.gen_mux.mst_w_valid, slv_reqs[0].w_valid);
    cg_inst.sample();
    check("w_valid passes through when not stalled (C)",
          dut.gen_mux.mst_w_valid === 1'b1);

    // Case D: w_fifo_empty=0, b_fifo_full=0, slave w_valid=0 -> mst_w_valid=0
    slv_reqs[0].w_valid = 1'b0;
    #1;
    check("w_valid stays low when slave w_valid=0 (D)",
          dut.gen_mux.mst_w_valid === 1'b0);

    release dut.gen_mux.w_fifo_empty;
    release dut.gen_mux.b_fifo_full;
    release dut.gen_mux.w_select;
  endtask

  // ---------------------------------------------------------------
  // Test 10: Verify that slv w_ready is NOT asserted for unselected
  //          slave when w channel is active.
  // ---------------------------------------------------------------
  task automatic test10_w_ready_only_for_selected_slave();
    $display("\n--- Test 10: w_ready only for selected slave ---");
    reset_dut();

    force dut.gen_mux.w_fifo_empty = 1'b0;
    force dut.gen_mux.b_fifo_full  = 1'b0;
    force dut.gen_mux.w_select = 0;
    force dut.gen_mux.mst_w_ready = 1'b1;

    slv_reqs[0].w_valid = 1'b1;
    slv_reqs[1].w_valid = 1'b1;
    #1;

    check("w_ready asserted for selected slave 0",
          slv_resps[0].w_ready === 1'b1);
    check("w_ready NOT asserted for unselected slave 1",
          slv_resps[1].w_ready === 1'b0);

    // Switch selection to slave 1
    force dut.gen_mux.w_select = 1;
    #1;

    check("w_ready NOT asserted for unselected slave 0 after switch",
          slv_resps[0].w_ready === 1'b0);
    check("w_ready asserted for selected slave 1 after switch",
          slv_resps[1].w_ready === 1'b1);

    release dut.gen_mux.w_fifo_empty;
    release dut.gen_mux.b_fifo_full;
    release dut.gen_mux.w_select;
    release dut.gen_mux.mst_w_ready;
  endtask

  // ---------------------------------------------------------------
  // Patch-focused covergroup: PR#245 removes unnecessary mux on W channel
  // so mst_w_chan always reflects slv_reqs_i[w_select].w regardless of
  // w_fifo_empty or b_fifo_full stall conditions.
  // ---------------------------------------------------------------
  int test_phase;

  covergroup cg_patch;
    cp_test_phase: coverpoint test_phase {
      bins wchan_fifo_empty     = {1};
      bins wchan_b_fifo_full    = {2};
      bins wchan_both_stalls    = {3};
      bins wchan_follows_select = {4};
      bins full_write_txn       = {5};
      bins two_slave_arb        = {6};
      bins comb_update          = {7};
      bins edge_patterns        = {8};
      bins w_valid_gating       = {9};
      bins w_ready_select       = {10};
    }
    // Cover the W channel data passthrough under stall (key fix behavior)
    cp_mst_w_valid: coverpoint mst_req.w_valid {
      bins active   = {1'b1};
      bins inactive = {1'b0};
    }
    // Cover stall conditions
    cp_w_stalled: coverpoint (mst_req.w_valid == 1'b0 && slv_reqs[0].w_valid == 1'b1) {
      bins stalled     = {1'b1};
      bins not_stalled = {1'b0};
    }
    // Illegal: failures indicate the mux was not properly removed
    cp_failures: coverpoint fail_count {
      bins no_failures = {0};
      illegal_bins mux_bug = {[1:$]};
    }
  endgroup

  cg_patch cg_inst = new();

  // ---------------------------------------------------------------
  // Main test sequence
  // ---------------------------------------------------------------
  initial begin
    pass_count = 0;
    fail_count = 0;

    test_phase = 1;  test1_wchan_not_zeroed_when_fifo_empty();       $display("[DBG%0d] w_valid=%b slv0_w_valid=%b stalled_expr=%b", test_phase, mst_req.w_valid, slv_reqs[0].w_valid, (mst_req.w_valid == 1'b0 && slv_reqs[0].w_valid == 1'b1)); cg_inst.sample();
    test_phase = 2;  test2_wchan_not_zeroed_when_b_fifo_full();      $display("[DBG%0d] w_valid=%b slv0_w_valid=%b stalled_expr=%b", test_phase, mst_req.w_valid, slv_reqs[0].w_valid, (mst_req.w_valid == 1'b0 && slv_reqs[0].w_valid == 1'b1)); cg_inst.sample();
    test_phase = 3;  test3_wchan_not_zeroed_both_stall_conditions(); $display("[DBG%0d] w_valid=%b slv0_w_valid=%b stalled_expr=%b", test_phase, mst_req.w_valid, slv_reqs[0].w_valid, (mst_req.w_valid == 1'b0 && slv_reqs[0].w_valid == 1'b1)); cg_inst.sample();
    test_phase = 4;  test4_wchan_follows_w_select();                 $display("[DBG%0d] w_valid=%b slv0_w_valid=%b stalled_expr=%b", test_phase, mst_req.w_valid, slv_reqs[0].w_valid, (mst_req.w_valid == 1'b0 && slv_reqs[0].w_valid == 1'b1)); cg_inst.sample();
    test_phase = 5;  test5_full_write_transaction();                 $display("[DBG%0d] w_valid=%b slv0_w_valid=%b stalled_expr=%b", test_phase, mst_req.w_valid, slv_reqs[0].w_valid, (mst_req.w_valid == 1'b0 && slv_reqs[0].w_valid == 1'b1)); cg_inst.sample();
    test_phase = 6;  test6_two_slave_arbitration();                  $display("[DBG%0d] w_valid=%b slv0_w_valid=%b stalled_expr=%b", test_phase, mst_req.w_valid, slv_reqs[0].w_valid, (mst_req.w_valid == 1'b0 && slv_reqs[0].w_valid == 1'b1)); cg_inst.sample();
    test_phase = 7;  test7_wchan_data_updates_combinationally();     $display("[DBG%0d] w_valid=%b slv0_w_valid=%b stalled_expr=%b", test_phase, mst_req.w_valid, slv_reqs[0].w_valid, (mst_req.w_valid == 1'b0 && slv_reqs[0].w_valid == 1'b1)); cg_inst.sample();
    test_phase = 8;  test8_edge_case_data_patterns();                $display("[DBG%0d] w_valid=%b slv0_w_valid=%b stalled_expr=%b", test_phase, mst_req.w_valid, slv_reqs[0].w_valid, (mst_req.w_valid == 1'b0 && slv_reqs[0].w_valid == 1'b1)); cg_inst.sample();
    test_phase = 9;  test9_mst_w_valid_gating();                    $display("[DBG%0d] w_valid=%b slv0_w_valid=%b stalled_expr=%b", test_phase, mst_req.w_valid, slv_reqs[0].w_valid, (mst_req.w_valid == 1'b0 && slv_reqs[0].w_valid == 1'b1)); cg_inst.sample();
    test_phase = 10; test10_w_ready_only_for_selected_slave();       $display("[DBG%0d] w_valid=%b slv0_w_valid=%b stalled_expr=%b", test_phase, mst_req.w_valid, slv_reqs[0].w_valid, (mst_req.w_valid == 1'b0 && slv_reqs[0].w_valid == 1'b1)); cg_inst.sample();

    $display("\n============================================");
    $display("  Test Summary: %0d PASSED, %0d FAILED", pass_count, fail_count);
    $display("============================================");

    if (fail_count > 0) begin
      $display("FAIL: Some tests did not pass.");
      $fatal(1, "Testbench FAILED");
    end else begin
      $display("PASS: All tests passed.");
    end

    $display("Functional Coverage: %.1f%%", cg_inst.get_coverage());
    $finish;
  end

  // Timeout watchdog
  initial begin
    #100_000;
    $display("ERROR: Simulation timed out!");
    $fatal(1, "Timeout");
  end

  initial begin
    $dumpfile("tb_axi_lite_mux_wchannel_patch.vcd");
    $dumpvars(0);
  end

endmodule

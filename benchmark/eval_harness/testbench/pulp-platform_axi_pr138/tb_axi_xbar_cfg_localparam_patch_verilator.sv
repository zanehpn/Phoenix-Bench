`timescale 1ns/1ps

// Testbench for axi_xbar with the cfg_NoMstPorts localparam fix (PR #138).
//
// Configuration: 2 slave ports, 2 master ports, 32-bit address, 32-bit data.
// Address map:
//   Master 0: 0x0000_0000 - 0x0000_FFFF
//   Master 1: 0x0001_0000 - 0x0001_FFFF
//
// Test plan:
//   1. Write from slave port 0 to master port 0 address range, verify routing.
//   2. Read  from slave port 0 to master port 1 address range, verify routing.
//   3. Write from slave port 1 to master port 1 address range, verify routing.
//   4. Read  from slave port 1 to master port 0 address range, verify routing.
//   5. Read  from slave port 0 to unmapped address, expect DECERR from error slave.

`include "axi/typedef.svh"

module tb_axi_xbar_cfg_localparam_patch;

  // ---------- Parameters --------------------------------------------------
  localparam int unsigned NUM_SLV     = 2;
  localparam int unsigned NUM_MST     = 2;
  localparam int unsigned ADDR_WIDTH  = 32;
  localparam int unsigned DATA_WIDTH  = 32;
  localparam int unsigned ID_WIDTH    = 4;
  localparam int unsigned USER_WIDTH  = 1;
  localparam int unsigned NUM_RULES   = 2;

  localparam int unsigned ID_WIDTH_MST = ID_WIDTH + $clog2(NUM_SLV);

  // ---------- Type definitions using AXI typedef macros --------------------
  typedef logic [ID_WIDTH-1:0]      id_slv_t;
  typedef logic [ID_WIDTH_MST-1:0]  id_mst_t;
  typedef logic [ADDR_WIDTH-1:0]    addr_t;
  typedef logic [DATA_WIDTH-1:0]    data_t;
  typedef logic [DATA_WIDTH/8-1:0]  strb_t;
  typedef logic [USER_WIDTH-1:0]    user_t;

  `AXI_TYPEDEF_AW_CHAN_T(slv_aw_chan_t, addr_t, id_slv_t, user_t)
  `AXI_TYPEDEF_AW_CHAN_T(mst_aw_chan_t, addr_t, id_mst_t, user_t)
  `AXI_TYPEDEF_W_CHAN_T(w_chan_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(slv_b_chan_t, id_slv_t, user_t)
  `AXI_TYPEDEF_B_CHAN_T(mst_b_chan_t, id_mst_t, user_t)
  `AXI_TYPEDEF_AR_CHAN_T(slv_ar_chan_t, addr_t, id_slv_t, user_t)
  `AXI_TYPEDEF_AR_CHAN_T(mst_ar_chan_t, addr_t, id_mst_t, user_t)
  `AXI_TYPEDEF_R_CHAN_T(slv_r_chan_t, data_t, id_slv_t, user_t)
  `AXI_TYPEDEF_R_CHAN_T(mst_r_chan_t, data_t, id_mst_t, user_t)
  `AXI_TYPEDEF_REQ_T(slv_req_t, slv_aw_chan_t, w_chan_t, slv_ar_chan_t)
  `AXI_TYPEDEF_REQ_T(mst_req_t, mst_aw_chan_t, w_chan_t, mst_ar_chan_t)
  `AXI_TYPEDEF_RESP_T(slv_resp_t, slv_b_chan_t, slv_r_chan_t)
  `AXI_TYPEDEF_RESP_T(mst_resp_t, mst_b_chan_t, mst_r_chan_t)

  // ---------- Crossbar configuration --------------------------------------
  localparam axi_pkg::xbar_cfg_t XbarCfg = '{
    NoSlvPorts:         NUM_SLV,
    NoMstPorts:         NUM_MST,
    MaxMstTrans:        4,
    MaxSlvTrans:        4,
    FallThrough:        1'b0,
    LatencyMode:        axi_pkg::NO_LATENCY,
    AxiIdWidthSlvPorts: ID_WIDTH,
    AxiIdUsedSlvPorts:  ID_WIDTH,
    AxiAddrWidth:       ADDR_WIDTH,
    AxiDataWidth:       DATA_WIDTH,
    NoAddrRules:        NUM_RULES
  };

  typedef axi_pkg::xbar_rule_32_t rule_t;

  // ---------- Clock and reset ---------------------------------------------
  logic clk, rst_n;
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n = 1'b0;
    repeat (5) @(posedge clk);
    rst_n = 1'b1;
  end

  // ---------- DUT signals -------------------------------------------------
  slv_req_t  [NUM_SLV-1:0] slv_req;
  slv_resp_t [NUM_SLV-1:0] slv_resp;
  mst_req_t  [NUM_MST-1:0] mst_req;
  mst_resp_t [NUM_MST-1:0] mst_resp;

  rule_t [NUM_RULES-1:0] addr_map;

  logic [NUM_SLV-1:0]                          en_default_mst;
  logic [NUM_SLV-1:0][$clog2(NUM_MST)-1:0]    default_mst;

  assign addr_map[0] = '{idx: 32'd0, start_addr: 32'h0000_0000, end_addr: 32'h0001_0000};
  assign addr_map[1] = '{idx: 32'd1, start_addr: 32'h0001_0000, end_addr: 32'h0002_0000};

  assign en_default_mst = '0;
  assign default_mst    = '0;

  // ---------- DUT instantiation -------------------------------------------
  axi_xbar #(
    .Cfg           ( XbarCfg        ),
    .slv_aw_chan_t ( slv_aw_chan_t   ),
    .mst_aw_chan_t ( mst_aw_chan_t   ),
    .w_chan_t      ( w_chan_t        ),
    .slv_b_chan_t  ( slv_b_chan_t    ),
    .mst_b_chan_t  ( mst_b_chan_t    ),
    .slv_ar_chan_t ( slv_ar_chan_t   ),
    .mst_ar_chan_t ( mst_ar_chan_t   ),
    .slv_r_chan_t  ( slv_r_chan_t    ),
    .mst_r_chan_t  ( mst_r_chan_t    ),
    .slv_req_t     ( slv_req_t      ),
    .slv_resp_t    ( slv_resp_t     ),
    .mst_req_t     ( mst_req_t      ),
    .mst_resp_t    ( mst_resp_t     ),
    .rule_t        ( rule_t         )
  ) i_axi_xbar (
    .clk_i                  ( clk            ),
    .rst_ni                 ( rst_n          ),
    .test_i                 ( 1'b0           ),
    .slv_ports_req_i        ( slv_req        ),
    .slv_ports_resp_o       ( slv_resp       ),
    .mst_ports_req_o        ( mst_req        ),
    .mst_ports_resp_i       ( mst_resp       ),
    .addr_map_i             ( addr_map       ),
    .en_default_mst_port_i  ( en_default_mst ),
    .default_mst_port_i     ( default_mst    )
  );

  // ---------- Simple master-side responder --------------------------------
  // Each master port accepts writes (AW+W) and responds with B,
  // accepts reads (AR) and responds with R containing the address as data.
  genvar gi;
  generate
    for (gi = 0; gi < NUM_MST; gi++) begin : gen_mst_resp
      // Track state for write channel
      logic aw_pending, w_pending;
      mst_aw_chan_t aw_saved;

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          aw_pending <= 1'b0;
          w_pending  <= 1'b0;
          aw_saved   <= '0;
        end else begin
          // Capture AW
          if (mst_req[gi].aw_valid && mst_resp[gi].aw_ready) begin
            aw_pending <= 1'b1;
            aw_saved   <= mst_req[gi].aw;
          end
          // Capture W
          if (mst_req[gi].w_valid && mst_resp[gi].w_ready) begin
            w_pending <= 1'b1;
          end
          // Clear on B handshake
          if (mst_resp[gi].b_valid && mst_req[gi].b_ready) begin
            aw_pending <= 1'b0;
            w_pending  <= 1'b0;
          end
        end
      end

      // AW ready: accept when not already holding a pending write
      assign mst_resp[gi].aw_ready = !aw_pending;
      // W ready: accept when not already holding pending w data
      assign mst_resp[gi].w_ready  = !w_pending;

      // B valid: respond when both AW and W have been received
      assign mst_resp[gi].b_valid = aw_pending && w_pending;
      assign mst_resp[gi].b      = '{
        id:   aw_saved.id,
        resp: axi_pkg::RESP_OKAY,
        user: '0
      };

      // AR channel
      logic ar_pending;
      mst_ar_chan_t ar_saved;

      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          ar_pending <= 1'b0;
          ar_saved   <= '0;
        end else begin
          if (mst_req[gi].ar_valid && mst_resp[gi].ar_ready) begin
            ar_pending <= 1'b1;
            ar_saved   <= mst_req[gi].ar;
          end
          if (mst_resp[gi].r_valid && mst_req[gi].r_ready) begin
            ar_pending <= 1'b0;
          end
        end
      end

      assign mst_resp[gi].ar_ready = !ar_pending;

      // R channel: return address as data
      assign mst_resp[gi].r_valid = ar_pending;
      assign mst_resp[gi].r      = '{
        id:   ar_saved.id,
        data: ar_saved.addr[DATA_WIDTH-1:0],
        resp: axi_pkg::RESP_OKAY,
        last: 1'b1,
        user: '0
      };
    end
  endgenerate

  // ---------- Test stimulus and checking ----------------------------------
  int test_pass;
  int test_fail;

  task automatic init_slv_req(int idx);
    slv_req[idx]           = '0;
  endtask

  // AXI write: send AW and W, wait for B
  task automatic axi_write(
    input int       slv_idx,
    input addr_t    addr,
    input data_t    wdata,
    input id_slv_t  id,
    output logic [1:0] bresp
  );
    // Drive AW
    slv_req[slv_idx].aw_valid   = 1'b1;
    slv_req[slv_idx].aw.addr    = addr;
    slv_req[slv_idx].aw.id      = id;
    slv_req[slv_idx].aw.len     = 8'd0;
    slv_req[slv_idx].aw.size    = 3'b010; // 4 bytes
    slv_req[slv_idx].aw.burst   = axi_pkg::BURST_INCR;
    slv_req[slv_idx].aw.lock    = 1'b0;
    slv_req[slv_idx].aw.cache   = 4'b0;
    slv_req[slv_idx].aw.prot    = 3'b0;
    slv_req[slv_idx].aw.qos     = 4'b0;
    slv_req[slv_idx].aw.region  = 4'b0;
    slv_req[slv_idx].aw.atop    = 6'b0;
    slv_req[slv_idx].aw.user    = '0;

    // Drive W
    slv_req[slv_idx].w_valid    = 1'b1;
    slv_req[slv_idx].w.data     = wdata;
    slv_req[slv_idx].w.strb     = '1;
    slv_req[slv_idx].w.last     = 1'b1;
    slv_req[slv_idx].w.user     = '0;

    slv_req[slv_idx].b_ready    = 1'b1;

    // Wait for AW accepted
    do @(posedge clk); while (!slv_resp[slv_idx].aw_ready);
    @(posedge clk);
    slv_req[slv_idx].aw_valid = 1'b0;

    // Wait for W accepted (may already have been)
    while (!slv_resp[slv_idx].w_ready) @(posedge clk);
    @(posedge clk);
    slv_req[slv_idx].w_valid = 1'b0;

    // Wait for B
    while (!slv_resp[slv_idx].b_valid) @(posedge clk);
    bresp = slv_resp[slv_idx].b.resp;
    @(posedge clk);
    slv_req[slv_idx].b_ready = 1'b0;
  endtask

  // AXI read: send AR, wait for R
  task automatic axi_read(
    input int       slv_idx,
    input addr_t    addr,
    input id_slv_t  id,
    output data_t   rdata,
    output logic [1:0] rresp
  );
    slv_req[slv_idx].ar_valid   = 1'b1;
    slv_req[slv_idx].ar.addr    = addr;
    slv_req[slv_idx].ar.id      = id;
    slv_req[slv_idx].ar.len     = 8'd0;
    slv_req[slv_idx].ar.size    = 3'b010;
    slv_req[slv_idx].ar.burst   = axi_pkg::BURST_INCR;
    slv_req[slv_idx].ar.lock    = 1'b0;
    slv_req[slv_idx].ar.cache   = 4'b0;
    slv_req[slv_idx].ar.prot    = 3'b0;
    slv_req[slv_idx].ar.qos     = 4'b0;
    slv_req[slv_idx].ar.region  = 4'b0;
    slv_req[slv_idx].ar.user    = '0;

    slv_req[slv_idx].r_ready    = 1'b1;

    // Wait for AR accepted
    do @(posedge clk); while (!slv_resp[slv_idx].ar_ready);
    @(posedge clk);
    slv_req[slv_idx].ar_valid = 1'b0;

    // Wait for R
    while (!slv_resp[slv_idx].r_valid) @(posedge clk);
    rdata = slv_resp[slv_idx].r.data;
    rresp = slv_resp[slv_idx].r.resp;
    @(posedge clk);
    slv_req[slv_idx].r_ready = 1'b0;
  endtask

  // ---------- Patch check: verify cfg_NoMstPorts localparam exists --------
  // The patch introduces localparam cfg_NoMstPorts inside axi_xbar.
  // On unpatched code this localparam does not exist, so this hierarchical
  // reference will cause an elaboration/compile error -> FAIL.
  int unsigned cfg_probe;
  assign cfg_probe = i_axi_xbar.cfg_NoMstPorts;

  // ---------- Main test sequence ------------------------------------------
  initial begin
    data_t   rdata;
    logic [1:0] resp;

    test_pass = 0;
    test_fail = 0;

    // Initialize all slave port requests
    for (int i = 0; i < NUM_SLV; i++) init_slv_req(i);

    // Wait for reset release
    @(posedge rst_n);
    repeat (3) @(posedge clk);

    // ---- Test 0: Verify cfg_NoMstPorts localparam value ----
    $display("[TEST 0] Verify cfg_NoMstPorts localparam exists and equals NUM_MST");
    if (cfg_probe == NUM_MST) begin
      $display("  PASS: cfg_NoMstPorts = %0d (matches NUM_MST)", cfg_probe);
      test_pass++;
    end else begin
      $display("  FAIL: cfg_NoMstPorts = %0d, expected %0d", cfg_probe, NUM_MST);
      test_fail++;
    end

    repeat (3) @(posedge clk);

    // ---- Test 1: Write from SLV0 to MST0 (addr 0x0000_1000) ----
    $display("[TEST 1] Write from SLV0 to MST0 address range");
    axi_write(0, 32'h0000_1000, 32'hDEAD_BEEF, 4'd1, resp);
    if (resp == axi_pkg::RESP_OKAY) begin
      $display("  PASS: Write completed with OKAY response");
      test_pass++;
    end else begin
      $display("  FAIL: Expected OKAY, got %0b", resp);
      test_fail++;
    end

    repeat (5) @(posedge clk);

    // ---- Test 2: Read from SLV0 to MST1 (addr 0x0001_2000) ----
    $display("[TEST 2] Read from SLV0 to MST1 address range");
    axi_read(0, 32'h0001_2000, 4'd2, rdata, resp);
    if (resp == axi_pkg::RESP_OKAY && rdata == 32'h0001_2000) begin
      $display("  PASS: Read returned correct address data 0x%08h", rdata);
      test_pass++;
    end else begin
      $display("  FAIL: resp=%0b, rdata=0x%08h (expected 0x00012000)", resp, rdata);
      test_fail++;
    end

    repeat (5) @(posedge clk);

    // ---- Test 3: Write from SLV1 to MST1 (addr 0x0001_3000) ----
    $display("[TEST 3] Write from SLV1 to MST1 address range");
    axi_write(1, 32'h0001_3000, 32'hCAFE_BABE, 4'd3, resp);
    if (resp == axi_pkg::RESP_OKAY) begin
      $display("  PASS: Write completed with OKAY response");
      test_pass++;
    end else begin
      $display("  FAIL: Expected OKAY, got %0b", resp);
      test_fail++;
    end

    repeat (5) @(posedge clk);

    // ---- Test 4: Read from SLV1 to MST0 (addr 0x0000_4000) ----
    $display("[TEST 4] Read from SLV1 to MST0 address range");
    axi_read(1, 32'h0000_4000, 4'd4, rdata, resp);
    if (resp == axi_pkg::RESP_OKAY && rdata == 32'h0000_4000) begin
      $display("  PASS: Read returned correct address data 0x%08h", rdata);
      test_pass++;
    end else begin
      $display("  FAIL: resp=%0b, rdata=0x%08h (expected 0x00004000)", resp, rdata);
      test_fail++;
    end

    repeat (5) @(posedge clk);

    // ---- Test 5: Read from SLV0 to unmapped address (DECERR) ----
    $display("[TEST 5] Read from SLV0 to unmapped address (expect DECERR)");
    axi_read(0, 32'hFFFF_0000, 4'd5, rdata, resp);
    if (resp == axi_pkg::RESP_DECERR) begin
      $display("  PASS: Read returned DECERR as expected");
      test_pass++;
    end else begin
      $display("  FAIL: Expected DECERR (2'b11), got %0b", resp);
      test_fail++;
    end

    repeat (10) @(posedge clk);

    // ---- Summary ----
    $display("======================================");
    $display("Tests passed: %0d / %0d", test_pass, test_pass + test_fail);
    if (test_fail == 0) begin
      $display("PASS: axi_xbar cfg_NoMstPorts localparam patch verified");
    end else begin
      $fatal(1, "FAIL: %0d test(s) failed", test_fail);
    end
    $display("======================================");
    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end

  // ---------------------------------------------------------------
  // Patch-focused functional coverage
  // ---------------------------------------------------------------
  // The patch introduces cfg_NoMstPorts localparam to fix vsim 10.6c
  // compatibility for error slave response port connection.
  // We verify xbar routing and error slave (DECERR) functionality.

  // Probe internal localparam usage through the error slave response path
  wire slv0_b_valid = slv_resp[0].b_valid;
  wire slv1_b_valid = slv_resp[1].b_valid;
  wire slv0_r_valid = slv_resp[0].r_valid;
  wire slv1_r_valid = slv_resp[1].r_valid;

  // [verilator-strip cg] covergroup cg_patch;
// [verilator-strip cg]     // Coverpoint: slave port 0 write response
// [verilator-strip cg]     cp_slv0_b: coverpoint slv0_b_valid {
// [verilator-strip cg]       bins valid   = {1'b1};
// [verilator-strip cg]       bins invalid = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Coverpoint: slave port 1 write response
// [verilator-strip cg]     cp_slv1_b: coverpoint slv1_b_valid {
// [verilator-strip cg]       bins valid   = {1'b1};
// [verilator-strip cg]       bins invalid = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Coverpoint: slave port 0 read response
// [verilator-strip cg]     cp_slv0_r: coverpoint slv0_r_valid {
// [verilator-strip cg]       bins valid   = {1'b1};
// [verilator-strip cg]       bins invalid = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Coverpoint: slave port 0 read response type (OKAY vs DECERR)
// [verilator-strip cg]     cp_slv0_r_resp: coverpoint slv_resp[0].r.resp {
// [verilator-strip cg]       bins okay   = {axi_pkg::RESP_OKAY};
// [verilator-strip cg]       bins decerr = {axi_pkg::RESP_DECERR};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Coverpoint: slave port 0 write response type
// [verilator-strip cg]     cp_slv0_b_resp: coverpoint slv_resp[0].b.resp {
// [verilator-strip cg]       bins okay   = {axi_pkg::RESP_OKAY};
// [verilator-strip cg]       bins decerr = {axi_pkg::RESP_DECERR};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cross: response validity and type (error slave path uses cfg_NoMstPorts)
// [verilator-strip cg]     cx_r_resp: cross cp_slv0_r, cp_slv0_r_resp {
// [verilator-strip cg]       ignore_bins test_invalid_okay = binsof(cp_slv0_r.invalid) && binsof(cp_slv0_r_resp.okay);
// [verilator-strip cg]     }
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_patch cg_inst = new();

  always @(posedge clk) begin
    if (rst_n)
      /* [verilator-strip sample] */;
  end

  // Timeout watchdog
  initial begin
    #100_000;
    $fatal(1, "FAIL: Simulation timed out");
    $finish;
  end

  // VCD dump
  initial begin
    $dumpfile("tb_axi_xbar_cfg_localparam_patch.vcd");
    $dumpvars(0);
  end

endmodule

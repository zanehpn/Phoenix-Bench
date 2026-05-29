`timescale 1ns/1ps

// Testbench for pulp-platform_axi PR#228:
// Verifies that axi_lite_mux_intf uses AXI_LITE (not AXI_BUS) interface ports,
// and that AXI-Lite write/read transactions pass through the mux correctly.
module tb_axi_lite_mux_intf_port_types;

  import axi_pkg::*;

  localparam int unsigned AXI_ADDR_WIDTH = 16;
  localparam int unsigned AXI_DATA_WIDTH = 32;
  localparam int unsigned AXI_STRB_WIDTH = AXI_DATA_WIDTH / 8;
  localparam int unsigned NO_SLV_PORTS   = 2;
  localparam int unsigned MAX_TRANS      = 2;

  logic clk;
  logic rst_ni;

  // Error counter
  int err_count = 0;

  // ---------------------------------------------------------------
  // AXI_LITE interfaces (the fix: these must be AXI_LITE, not AXI_BUS)
  // ---------------------------------------------------------------
  AXI_LITE #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
  ) slv_if [NO_SLV_PORTS-1:0] ();

  AXI_LITE #(
    .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
    .AXI_DATA_WIDTH(AXI_DATA_WIDTH)
  ) mst_if ();

  // ---------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------
  axi_lite_mux_intf #(
    .AxiAddrWidth(AXI_ADDR_WIDTH),
    .AxiDataWidth(AXI_DATA_WIDTH),
    .NoSlvPorts  (NO_SLV_PORTS),
    .MaxTrans    (MAX_TRANS),
    .FallThrough (1'b1),
    .SpillAw     (1'b0),
    .SpillW      (1'b0),
    .SpillB      (1'b0),
    .SpillAr     (1'b0),
    .SpillR      (1'b0)
  ) dut (
    .clk_i (clk),
    .rst_ni(rst_ni),
    .test_i(1'b0),
    .slv   (slv_if),
    .mst   (mst_if)
  );

  // ---------------------------------------------------------------
  // Clock generation
  // ---------------------------------------------------------------
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // ---------------------------------------------------------------
  // Simple AXI-Lite slave responder on the master port
  // Accepts writes (returns OKAY), accepts reads (returns address as data).
  // ---------------------------------------------------------------
  logic [AXI_ADDR_WIDTH-1:0] captured_aw_addr;
  logic [AXI_DATA_WIDTH-1:0] captured_w_data;
  logic [AXI_STRB_WIDTH-1:0] captured_w_strb;
  logic [AXI_ADDR_WIDTH-1:0] captured_ar_addr;

  // Write address channel - always ready
  assign mst_if.aw_ready = 1'b1;

  // Write data channel - always ready
  assign mst_if.w_ready  = 1'b1;

  // Write response channel
  logic b_pending;
  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      b_pending <= 1'b0;
    end else begin
      if (mst_if.w_valid && mst_if.w_ready) begin
        b_pending <= 1'b1;
        captured_w_data <= mst_if.w_data;
        captured_w_strb <= mst_if.w_strb;
      end
      if (mst_if.aw_valid && mst_if.aw_ready) begin
        captured_aw_addr <= mst_if.aw_addr;
      end
      if (mst_if.b_valid && mst_if.b_ready) begin
        b_pending <= 1'b0;
      end
    end
  end
  assign mst_if.b_valid = b_pending;
  assign mst_if.b_resp  = axi_pkg::RESP_OKAY;

  // Read address channel - always ready
  assign mst_if.ar_ready = 1'b1;

  // Read data channel - return address as data
  logic r_pending;
  logic [AXI_DATA_WIDTH-1:0] r_data_reg;
  always_ff @(posedge clk or negedge rst_ni) begin
    if (!rst_ni) begin
      r_pending  <= 1'b0;
      r_data_reg <= '0;
    end else begin
      if (mst_if.ar_valid && mst_if.ar_ready) begin
        r_pending  <= 1'b1;
        captured_ar_addr <= mst_if.ar_addr;
        // Return address zero-extended/truncated as read data
        r_data_reg <= {{(AXI_DATA_WIDTH-AXI_ADDR_WIDTH){1'b0}}, mst_if.ar_addr};
      end
      if (mst_if.r_valid && mst_if.r_ready) begin
        r_pending <= 1'b0;
      end
    end
  end
  assign mst_if.r_valid = r_pending;
  assign mst_if.r_data  = r_data_reg;
  assign mst_if.r_resp  = axi_pkg::RESP_OKAY;

  // ---------------------------------------------------------------
  // Per-port intermediate signals (avoids VCS non-constant index
  // into interface arrays inside tasks)
  // ---------------------------------------------------------------
  logic [AXI_ADDR_WIDTH-1:0] port_aw_addr  [NO_SLV_PORTS];
  logic [2:0]                port_aw_prot  [NO_SLV_PORTS];
  logic                      port_aw_valid [NO_SLV_PORTS];
  logic                      port_aw_ready [NO_SLV_PORTS];
  logic [AXI_DATA_WIDTH-1:0] port_w_data   [NO_SLV_PORTS];
  logic [AXI_STRB_WIDTH-1:0] port_w_strb   [NO_SLV_PORTS];
  logic                      port_w_valid  [NO_SLV_PORTS];
  logic                      port_w_ready  [NO_SLV_PORTS];
  logic                      port_b_ready  [NO_SLV_PORTS];
  logic                      port_b_valid  [NO_SLV_PORTS];
  logic [AXI_ADDR_WIDTH-1:0] port_ar_addr  [NO_SLV_PORTS];
  logic [2:0]                port_ar_prot  [NO_SLV_PORTS];
  logic                      port_ar_valid [NO_SLV_PORTS];
  logic                      port_ar_ready [NO_SLV_PORTS];
  logic                      port_r_ready  [NO_SLV_PORTS];
  logic                      port_r_valid  [NO_SLV_PORTS];
  logic [AXI_DATA_WIDTH-1:0] port_r_data   [NO_SLV_PORTS];

  for (genvar g = 0; g < NO_SLV_PORTS; g++) begin : gen_port_connect
    assign slv_if[g].aw_addr  = port_aw_addr[g];
    assign slv_if[g].aw_prot  = port_aw_prot[g];
    assign slv_if[g].aw_valid = port_aw_valid[g];
    assign port_aw_ready[g]   = slv_if[g].aw_ready;
    assign slv_if[g].w_data   = port_w_data[g];
    assign slv_if[g].w_strb   = port_w_strb[g];
    assign slv_if[g].w_valid  = port_w_valid[g];
    assign port_w_ready[g]    = slv_if[g].w_ready;
    assign slv_if[g].b_ready  = port_b_ready[g];
    assign port_b_valid[g]    = slv_if[g].b_valid;
    assign slv_if[g].ar_addr  = port_ar_addr[g];
    assign slv_if[g].ar_prot  = port_ar_prot[g];
    assign slv_if[g].ar_valid = port_ar_valid[g];
    assign port_ar_ready[g]   = slv_if[g].ar_ready;
    assign slv_if[g].r_ready  = port_r_ready[g];
    assign port_r_valid[g]    = slv_if[g].r_valid;
    assign port_r_data[g]     = slv_if[g].r_data;
  end

  // ---------------------------------------------------------------
  // Tasks: drive AXI-Lite write/read on a slave port
  // ---------------------------------------------------------------

  // Drive a write transaction on slave port 'port'
  task automatic axi_lite_write(
    input int port,
    input logic [AXI_ADDR_WIDTH-1:0] addr,
    input logic [AXI_DATA_WIDTH-1:0] data,
    input logic [AXI_STRB_WIDTH-1:0] strb
  );
    // AW channel
    fork
      begin
        // Send AW
        @(posedge clk);
        port_aw_addr[port]  = addr;
        port_aw_prot[port]  = 3'b000;
        port_aw_valid[port] = 1'b1;
        do @(posedge clk); while (!port_aw_ready[port]);
        port_aw_valid[port] = 1'b0;
      end
      begin
        // Send W
        @(posedge clk);
        port_w_data[port]  = data;
        port_w_strb[port]  = strb;
        port_w_valid[port] = 1'b1;
        do @(posedge clk); while (!port_w_ready[port]);
        port_w_valid[port] = 1'b0;
      end
    join
    // Wait for B response
    port_b_ready[port] = 1'b1;
    do @(posedge clk); while (!port_b_valid[port]);
    @(posedge clk);
    port_b_ready[port] = 1'b0;
  endtask

  // Drive a read transaction on slave port 'port', return data
  task automatic axi_lite_read(
    input  int port,
    input  logic [AXI_ADDR_WIDTH-1:0] addr,
    output logic [AXI_DATA_WIDTH-1:0] data
  );
    // AR channel
    @(posedge clk);
    port_ar_addr[port]  = addr;
    port_ar_prot[port]  = 3'b000;
    port_ar_valid[port] = 1'b1;
    do @(posedge clk); while (!port_ar_ready[port]);
    port_ar_valid[port] = 1'b0;
    // Wait for R response
    port_r_ready[port] = 1'b1;
    do @(posedge clk); while (!port_r_valid[port]);
    data = port_r_data[port];
    @(posedge clk);
    port_r_ready[port] = 1'b0;
  endtask

  // ---------------------------------------------------------------
  // Initialize all slave port signals
  // ---------------------------------------------------------------
  initial begin
    for (int i = 0; i < NO_SLV_PORTS; i++) begin
      port_aw_addr[i]  = '0;
      port_aw_prot[i]  = '0;
      port_aw_valid[i] = 1'b0;
      port_w_data[i]   = '0;
      port_w_strb[i]   = '0;
      port_w_valid[i]  = 1'b0;
      port_b_ready[i]  = 1'b0;
      port_ar_addr[i]  = '0;
      port_ar_prot[i]  = '0;
      port_ar_valid[i] = 1'b0;
      port_r_ready[i]  = 1'b0;
    end
  end

  // ---------------------------------------------------------------
  // Patch-focused covergroup: PR#228 fixes AXI_BUS -> AXI_LITE
  // port type on axi_lite_mux_intf slv/mst interfaces.
  // ---------------------------------------------------------------
  int test_phase;

  // [verilator-strip cg] covergroup cg_patch @(posedge clk);
// [verilator-strip cg]     // Cover that AXI_LITE interface is used (compilation proves this)
// [verilator-strip cg]     cp_test_phase: coverpoint test_phase {
// [verilator-strip cg]       bins compilation_check  = {1};
// [verilator-strip cg]       bins write_port0        = {2};
// [verilator-strip cg]       bins write_port1        = {3};
// [verilator-strip cg]       bins read_port0         = {4};
// [verilator-strip cg]       bins read_port1         = {5};
// [verilator-strip cg]       bins signal_set_check   = {6};
// [verilator-strip cg]       bins b2b_writes         = {7};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cover AXI-Lite write handshake signals at master interface
// [verilator-strip cg]     cp_mst_aw_valid: coverpoint mst_if.aw_valid {
// [verilator-strip cg]       bins active   = {1'b1};
// [verilator-strip cg]       bins inactive = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_mst_w_valid: coverpoint mst_if.w_valid {
// [verilator-strip cg]       bins active   = {1'b1};
// [verilator-strip cg]       bins inactive = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cover read path
// [verilator-strip cg]     cp_mst_ar_valid: coverpoint mst_if.ar_valid {
// [verilator-strip cg]       bins active   = {1'b1};
// [verilator-strip cg]       bins inactive = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cover B response
// [verilator-strip cg]     cp_mst_b_valid: coverpoint mst_if.b_valid {
// [verilator-strip cg]       bins active   = {1'b1};
// [verilator-strip cg]       bins inactive = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cover R response
// [verilator-strip cg]     cp_mst_r_valid: coverpoint mst_if.r_valid {
// [verilator-strip cg]       bins active   = {1'b1};
// [verilator-strip cg]       bins inactive = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_patch cg_inst = new();

  // ---------------------------------------------------------------
  // Main test sequence
  // ---------------------------------------------------------------
  logic [AXI_DATA_WIDTH-1:0] rd_data;

  initial begin
    rst_ni = 1'b0;
    repeat (4) @(posedge clk);
    rst_ni = 1'b1;
    repeat (2) @(posedge clk);

    // ----------------------------------------------------------
    // Test 1: Instantiation with AXI_LITE interfaces compiles
    // ----------------------------------------------------------
    // If we get here, the DUT accepted AXI_LITE ports (not AXI_BUS).
    test_phase = 1;
    @(posedge clk); // ensure test_phase=1 is sampled
    $display("TEST 1 PASSED: axi_lite_mux_intf instantiation with AXI_LITE interfaces succeeded.");

    // ----------------------------------------------------------
    // Test 2: Write transaction from slave port 0
    // ----------------------------------------------------------
    test_phase = 2;
    axi_lite_write(0, 16'hABCD, 32'hDEAD_BEEF, 4'hF);
    // auto-sampled on posedge clk
    if (captured_aw_addr === 16'hABCD && captured_w_data === 32'hDEAD_BEEF && captured_w_strb === 4'hF) begin
      $display("TEST 2 PASSED: Write from slave port 0 forwarded correctly (addr=0x%04h, data=0x%08h, strb=0x%01h).",
               captured_aw_addr, captured_w_data, captured_w_strb);
    end else begin
      $display("TEST 2 FAILED: Write from slave port 0 mismatch. Got addr=0x%04h (exp 0xABCD), data=0x%08h (exp 0xDEADBEEF), strb=0x%01h (exp 0xF).",
               captured_aw_addr, captured_w_data, captured_w_strb);
      err_count++;
    end

    // ----------------------------------------------------------
    // Test 3: Write transaction from slave port 1
    // ----------------------------------------------------------
    test_phase = 3;
    axi_lite_write(1, 16'h1234, 32'hCAFE_BABE, 4'hA);
    // auto-sampled on posedge clk
    if (captured_aw_addr === 16'h1234 && captured_w_data === 32'hCAFE_BABE && captured_w_strb === 4'hA) begin
      $display("TEST 3 PASSED: Write from slave port 1 forwarded correctly (addr=0x%04h, data=0x%08h, strb=0x%01h).",
               captured_aw_addr, captured_w_data, captured_w_strb);
    end else begin
      $display("TEST 3 FAILED: Write from slave port 1 mismatch. Got addr=0x%04h (exp 0x1234), data=0x%08h (exp 0xCAFEBABE), strb=0x%01h (exp 0xA).",
               captured_aw_addr, captured_w_data, captured_w_strb);
      err_count++;
    end

    // ----------------------------------------------------------
    // Test 4: Read transaction from slave port 0
    // ----------------------------------------------------------
    test_phase = 4;
    axi_lite_read(0, 16'h5678, rd_data);
    // auto-sampled on posedge clk
    if (rd_data === {{(AXI_DATA_WIDTH-AXI_ADDR_WIDTH){1'b0}}, 16'h5678}) begin
      $display("TEST 4 PASSED: Read from slave port 0 returned correct data (0x%08h).", rd_data);
    end else begin
      $display("TEST 4 FAILED: Read from slave port 0 data mismatch. Got 0x%08h, expected 0x%08h.",
               rd_data, {{(AXI_DATA_WIDTH-AXI_ADDR_WIDTH){1'b0}}, 16'h5678});
      err_count++;
    end

    // ----------------------------------------------------------
    // Test 5: Read transaction from slave port 1
    // ----------------------------------------------------------
    test_phase = 5;
    axi_lite_read(1, 16'h9ABC, rd_data);
    // auto-sampled on posedge clk
    if (rd_data === {{(AXI_DATA_WIDTH-AXI_ADDR_WIDTH){1'b0}}, 16'h9ABC}) begin
      $display("TEST 5 PASSED: Read from slave port 1 returned correct data (0x%08h).", rd_data);
    end else begin
      $display("TEST 5 FAILED: Read from slave port 1 data mismatch. Got 0x%08h, expected 0x%08h.",
               rd_data, {{(AXI_DATA_WIDTH-AXI_ADDR_WIDTH){1'b0}}, 16'h9ABC});
      err_count++;
    end

    // ----------------------------------------------------------
    // Test 6: Verify AXI_LITE signal set (no AXI_BUS-only signals)
    // The AXI_LITE interface has only addr, prot, valid, ready on AW/AR.
    // AXI_BUS would additionally have id, len, size, burst, lock, cache,
    // qos, region, atop, user. If the port type were AXI_BUS, the
    // internal assign macros (`AXI_LITE_ASSIGN_TO_REQ`, etc.) would fail
    // to compile because they reference only AXI_LITE-specific signals.
    // Reaching this point proves the interface is AXI_LITE.
    // ----------------------------------------------------------
    test_phase = 6;
    // auto-sampled on posedge clk
    $display("TEST 6 PASSED: DUT compiled with AXI_LITE macros, confirming ports are AXI_LITE (not AXI_BUS).");

    // ----------------------------------------------------------
    // Test 7: Multiple back-to-back writes from different ports
    // ----------------------------------------------------------
    begin
      logic [AXI_ADDR_WIDTH-1:0] addrs [4] = '{16'h0010, 16'h0020, 16'h0030, 16'h0040};
      logic [AXI_DATA_WIDTH-1:0] datas [4] = '{32'h11111111, 32'h22222222, 32'h33333333, 32'h44444444};
      int test7_ok = 1;
      for (int i = 0; i < 4; i++) begin
        axi_lite_write(i % NO_SLV_PORTS, addrs[i], datas[i], 4'hF);
        if (captured_aw_addr !== addrs[i] || captured_w_data !== datas[i]) begin
          $display("TEST 7 FAILED: Back-to-back write %0d mismatch. addr=0x%04h (exp 0x%04h), data=0x%08h (exp 0x%08h).",
                   i, captured_aw_addr, addrs[i], captured_w_data, datas[i]);
          test7_ok = 0;
          err_count++;
        end
      end
      test_phase = 7;
      // auto-sampled on posedge clk
      if (test7_ok)
        $display("TEST 7 PASSED: 4 back-to-back writes from alternating ports forwarded correctly.");
    end

    // ----------------------------------------------------------
    // Summary
    // ----------------------------------------------------------
    repeat (4) @(posedge clk);
    if (err_count == 0) begin
      $display("PASS: All 7 tests passed. axi_lite_mux_intf correctly uses AXI_LITE interfaces and forwards transactions.");
    end else begin
      $fatal(1, "FAIL: %0d test(s) failed.", err_count);
    end
    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end

  // ---------------------------------------------------------------
  // Timeout watchdog
  // ---------------------------------------------------------------
  initial begin
    #50000;
    $fatal(1, "FAIL: Testbench timed out.");
    $finish;
  end

  // ---------------------------------------------------------------
  // Waveform dump
  // ---------------------------------------------------------------
  initial begin
    $dumpfile("tb_axi_lite_mux_intf_port_types.vcd");
    $dumpvars(0);
  end

endmodule

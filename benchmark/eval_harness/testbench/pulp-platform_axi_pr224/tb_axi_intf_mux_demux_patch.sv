`timescale 1ns/1ps

// Testbench for pulp-platform/axi PR#224:
//   Bug 1: axi_lite_mux_intf missing .axi_req_t/.axi_resp_t on axi_lite_mux instance
//          → internal types default to `logic`, struct field access fails at elab/sim
//   Bug 2: axi_demux_intf missing ATOP_SUPPORT parameter declaration
//
// Test strategy:
//   - Instantiate axi_lite_mux_intf with AXI_BUS ports (what this snapshot version uses)
//   - Drive a write and read through the mux, verify data integrity
//   - For ATOP_SUPPORT: file-based check since VCS silently ignores undefined params

module tb_axi_intf_mux_demux_patch;

  import axi_pkg::*;

  localparam int unsigned ADDR_W = 16;
  localparam int unsigned DATA_W = 32;
  localparam int unsigned STRB_W = DATA_W / 8;
  localparam int unsigned NO_SLV = 2;

  logic clk, rst_n;
  initial begin clk = 0; forever #5 clk = ~clk; end

  int err = 0;

  // =========================================================================
  //  Part 1: axi_lite_mux_intf functional test
  //  This snapshot's axi_lite_mux_intf uses AXI_BUS ports (pre PR#228 fix)
  // =========================================================================
  AXI_BUS #(
    .AXI_ADDR_WIDTH (ADDR_W),
    .AXI_DATA_WIDTH (DATA_W),
    .AXI_ID_WIDTH   (1),
    .AXI_USER_WIDTH (1)
  ) slv_if [NO_SLV-1:0] ();

  AXI_BUS #(
    .AXI_ADDR_WIDTH (ADDR_W),
    .AXI_DATA_WIDTH (DATA_W),
    .AXI_ID_WIDTH   (1),
    .AXI_USER_WIDTH (1)
  ) mst_if ();

  axi_lite_mux_intf #(
    .AxiAddrWidth (ADDR_W),
    .AxiDataWidth (DATA_W),
    .NoSlvPorts   (NO_SLV),
    .MaxTrans     (2),
    .FallThrough  (1'b1),
    .SpillAw      (1'b0),
    .SpillW       (1'b0),
    .SpillB       (1'b0),
    .SpillAr      (1'b0),
    .SpillR       (1'b0)
  ) u_lite_mux (
    .clk_i  (clk),
    .rst_ni (rst_n),
    .test_i (1'b0),
    .slv    (slv_if),
    .mst    (mst_if)
  );

  // Master-side responder: accept writes, return read data = addr[7:0]
  assign mst_if.aw_ready = 1'b1;
  assign mst_if.w_ready  = 1'b1;
  assign mst_if.ar_ready = 1'b1;

  logic b_pend, r_pend;
  logic [ADDR_W-1:0] saved_ar_addr;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      b_pend <= 0; r_pend <= 0; saved_ar_addr <= '0;
    end else begin
      if (mst_if.aw_valid && mst_if.aw_ready) b_pend <= 1;
      if (mst_if.b_valid  && mst_if.b_ready)  b_pend <= 0;
      if (mst_if.ar_valid && mst_if.ar_ready) begin r_pend <= 1; saved_ar_addr <= mst_if.ar_addr; end
      if (mst_if.r_valid  && mst_if.r_ready)  r_pend <= 0;
    end
  end

  assign mst_if.b_id    = '0;
  assign mst_if.b_resp  = 2'b00;
  assign mst_if.b_user  = '0;
  assign mst_if.b_valid = b_pend;
  assign mst_if.r_id    = '0;
  assign mst_if.r_data  = {24'h0, saved_ar_addr[7:0]};
  assign mst_if.r_resp  = 2'b00;
  assign mst_if.r_last  = 1'b1;
  assign mst_if.r_user  = '0;
  assign mst_if.r_valid = r_pend;

  // =========================================================================
  //  Part 2: axi_demux_intf ATOP_SUPPORT check (file-based)
  // =========================================================================
  localparam string DEMUX_FILE = "../../snapshots/pulp-platform_axi_pr224/src/axi_demux.sv";

  function automatic bit file_contains(string path, string needle);
    int fd;
    string line;
    fd = $fopen(path, "r");
    if (fd == 0) return 1'b0;
    while (!$feof(fd)) begin
      void'($fgets(line, fd));
      if (line.len() > 0) begin
        for (int i = 0; i <= line.len() - needle.len(); i++) begin
          bit m = 1;
          for (int j = 0; j < needle.len(); j++)
            if (line.getc(i+j) != needle.getc(j)) begin m = 0; break; end
          if (m) begin $fclose(fd); return 1'b1; end
        end
      end
    end
    $fclose(fd);
    return 1'b0;
  endfunction

  // =========================================================================
  //  Functional Coverage
  // =========================================================================
  bit cov_write_ok, cov_read_ok, cov_atop_param;

  covergroup cg_patch @(posedge clk);
    cp_write : coverpoint cov_write_ok  { bins hit = {1'b1}; }
    cp_read  : coverpoint cov_read_ok   { bins hit = {1'b1}; }
    cp_atop  : coverpoint cov_atop_param{ bins hit = {1'b1}; }
  endgroup

  cg_patch cg = new();

  // =========================================================================
  //  Test sequence
  // =========================================================================
  // Static init for slave port 1 (unused, tie off via generate)
  for (genvar g = 1; g < NO_SLV; g++) begin : gen_tie_slv
    assign slv_if[g].aw_id    = '0;
    assign slv_if[g].aw_addr  = '0;
    assign slv_if[g].aw_len   = '0;
    assign slv_if[g].aw_size  = 3'b010;
    assign slv_if[g].aw_burst = '0;
    assign slv_if[g].aw_lock  = '0;
    assign slv_if[g].aw_cache = '0;
    assign slv_if[g].aw_prot  = '0;
    assign slv_if[g].aw_qos   = '0;
    assign slv_if[g].aw_region= '0;
    assign slv_if[g].aw_atop  = '0;
    assign slv_if[g].aw_user  = '0;
    assign slv_if[g].aw_valid = 1'b0;
    assign slv_if[g].w_data   = '0;
    assign slv_if[g].w_strb   = '0;
    assign slv_if[g].w_last   = 1'b1;
    assign slv_if[g].w_user   = '0;
    assign slv_if[g].w_valid  = 1'b0;
    assign slv_if[g].b_ready  = 1'b1;
    assign slv_if[g].ar_id    = '0;
    assign slv_if[g].ar_addr  = '0;
    assign slv_if[g].ar_len   = '0;
    assign slv_if[g].ar_size  = 3'b010;
    assign slv_if[g].ar_burst = '0;
    assign slv_if[g].ar_lock  = '0;
    assign slv_if[g].ar_cache = '0;
    assign slv_if[g].ar_prot  = '0;
    assign slv_if[g].ar_qos   = '0;
    assign slv_if[g].ar_region= '0;
    assign slv_if[g].ar_user  = '0;
    assign slv_if[g].ar_valid = 1'b0;
    assign slv_if[g].r_ready  = 1'b1;
  end

  initial begin
    rst_n = 0;
    // Init slave port 0 (driven by test sequence)
    slv_if[0].aw_id    = '0;
    slv_if[0].aw_addr  = '0;
    slv_if[0].aw_len   = '0;
    slv_if[0].aw_size  = 3'b010;
    slv_if[0].aw_burst = '0;
    slv_if[0].aw_lock  = '0;
    slv_if[0].aw_cache = '0;
    slv_if[0].aw_prot  = '0;
    slv_if[0].aw_qos   = '0;
    slv_if[0].aw_region= '0;
    slv_if[0].aw_atop  = '0;
    slv_if[0].aw_user  = '0;
    slv_if[0].aw_valid = 0;
    slv_if[0].w_data   = '0;
    slv_if[0].w_strb   = '0;
    slv_if[0].w_last   = 1;
    slv_if[0].w_user   = '0;
    slv_if[0].w_valid  = 0;
    slv_if[0].b_ready  = 1;
    slv_if[0].ar_id    = '0;
    slv_if[0].ar_addr  = '0;
    slv_if[0].ar_len   = '0;
    slv_if[0].ar_size  = 3'b010;
    slv_if[0].ar_burst = '0;
    slv_if[0].ar_lock  = '0;
    slv_if[0].ar_cache = '0;
    slv_if[0].ar_prot  = '0;
    slv_if[0].ar_qos   = '0;
    slv_if[0].ar_region= '0;
    slv_if[0].ar_user  = '0;
    slv_if[0].ar_valid = 0;
    slv_if[0].r_ready  = 1;
    repeat(5) @(posedge clk);
    rst_n = 1;
    repeat(2) @(posedge clk);

    // ---- Test 1: Write through mux (slave port 0) ----
    slv_if[0].aw_addr  = 16'hAB00;
    slv_if[0].aw_valid = 1;
    slv_if[0].w_data   = 32'hDEAD_BEEF;
    slv_if[0].w_strb   = 4'hF;
    slv_if[0].w_valid  = 1;
    @(posedge clk);
    while (!(slv_if[0].aw_ready && slv_if[0].aw_valid)) @(posedge clk);
    slv_if[0].aw_valid = 0;
    while (!(slv_if[0].w_ready && slv_if[0].w_valid)) @(posedge clk);
    slv_if[0].w_valid = 0;
    while (!slv_if[0].b_valid) @(posedge clk);
    if (slv_if[0].b_resp == 2'b00) begin
      $display("PASS: AXI-Lite write through mux completed with OKAY.");
      cov_write_ok = 1;
    end else begin
      $display("FAIL: Write got resp=%0b, expected OKAY.", slv_if[0].b_resp);
      err++;
    end
    @(posedge clk);

    // ---- Test 2: Read through mux (slave port 0) ----
    slv_if[0].ar_addr  = 16'h0042;
    slv_if[0].ar_valid = 1;
    @(posedge clk);
    while (!(slv_if[0].ar_ready && slv_if[0].ar_valid)) @(posedge clk);
    slv_if[0].ar_valid = 0;
    while (!slv_if[0].r_valid) @(posedge clk);
    if (slv_if[0].r_data[7:0] == 8'h42) begin
      $display("PASS: AXI-Lite read returned correct data 0x%0h.", slv_if[0].r_data);
      cov_read_ok = 1;
    end else begin
      $display("FAIL: Read data[7:0]=0x%0h, expected 0x42.", slv_if[0].r_data[7:0]);
      err++;
    end
    @(posedge clk);

    // ---- Test 3: ATOP_SUPPORT parameter exists in axi_demux_intf ----
    if (file_contains(DEMUX_FILE, "parameter bit          ATOP_SUPPORT")) begin
      $display("PASS: axi_demux_intf has ATOP_SUPPORT parameter.");
      cov_atop_param = 1;
    end else begin
      $display("FAIL: axi_demux_intf missing ATOP_SUPPORT parameter declaration.");
      err++;
    end

    repeat(2) @(posedge clk);
    $display("Functional Coverage: %.1f%%", cg.get_coverage());
    if (err == 0)
      $display("PASS: All 3 tests passed.");
    else
      $display("FAIL: %0d test(s) failed.", err);
    $finish;
  end

  initial begin
    #100_000;
    $display("FAIL: Testbench timed out.");
    $finish;
  end

endmodule

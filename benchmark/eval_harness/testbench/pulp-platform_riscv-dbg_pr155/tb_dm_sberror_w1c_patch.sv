`timescale 1ns/1ps

module tb_dm_sberror_w1c_patch;

  import dm::*;

  localparam int unsigned NrHarts  = 1;
  localparam int unsigned BusWidth = 32;

  // -----------------------
  // DUT interface
  // -----------------------
  logic              clk_i;
  logic              rst_ni;
  logic              testmode_i;

  logic              dmi_rst_ni;
  logic              dmi_req_valid_i;
  logic              dmi_req_ready_o;
  dm::dmi_req_t      dmi_req_i;
  logic              dmi_resp_valid_o;
  logic              dmi_resp_ready_i;
  dm::dmi_resp_t     dmi_resp_o;

  logic              ndmreset_o;
  logic              dmactive_o;

  dm::hartinfo_t [NrHarts-1:0] hartinfo_i;
  logic          [NrHarts-1:0] halted_i;
  logic          [NrHarts-1:0] unavailable_i;
  logic          [NrHarts-1:0] resumeack_i;

  logic [19:0]        hartsel_o;
  logic [NrHarts-1:0] haltreq_o;
  logic [NrHarts-1:0] resumereq_o;
  logic               clear_resumeack_o;

  logic               cmd_valid_o;
  dm::command_t       cmd_o;
  logic               cmderror_valid_i;
  dm::cmderr_e        cmderror_i;
  logic               cmdbusy_i;

  logic [dm::ProgBufSize-1:0][31:0] progbuf_o;
  logic [dm::DataCount-1:0][31:0]   data_o;

  logic [dm::DataCount-1:0][31:0]   data_i;
  logic                             data_valid_i;

  logic [BusWidth-1:0] sbaddress_o;
  logic [BusWidth-1:0] sbaddress_i;
  logic                sbaddress_write_valid_o;

  logic                sbreadonaddr_o;
  logic                sbautoincrement_o;
  logic [2:0]          sbaccess_o;

  logic                sbreadondata_o;
  logic [BusWidth-1:0] sbdata_o;
  logic                sbdata_read_valid_o;
  logic                sbdata_write_valid_o;

  logic [BusWidth-1:0] sbdata_i;
  logic                sbdata_valid_i;

  logic                sbbusy_i;
  logic                sberror_valid_i;
  logic [2:0]          sberror_i;

  // -----------------------
  // Clock
  // -----------------------
  initial clk_i = 0;
  always #5 clk_i = ~clk_i; // 100 MHz

  // -----------------------
  // DUT
  // -----------------------
  dm_csrs #(
    .NrHarts ( NrHarts  ),
    .BusWidth( BusWidth )
  ) dut (
    .clk_i,
    .rst_ni,
    .testmode_i,
    .dmi_rst_ni,
    .dmi_req_valid_i,
    .dmi_req_ready_o,
    .dmi_req_i,
    .dmi_resp_valid_o,
    .dmi_resp_ready_i,
    .dmi_resp_o,
    .ndmreset_o,
    .dmactive_o,
    .hartinfo_i,
    .halted_i,
    .unavailable_i,
    .resumeack_i,
    .hartsel_o,
    .haltreq_o,
    .resumereq_o,
    .clear_resumeack_o,
    .cmd_valid_o,
    .cmd_o,
    .cmderror_valid_i,
    .cmderror_i,
    .cmdbusy_i,
    .progbuf_o,
    .data_o,
    .data_i,
    .data_valid_i,
    .sbaddress_o,
    .sbaddress_i,
    .sbaddress_write_valid_o,
    .sbreadonaddr_o,
    .sbautoincrement_o,
    .sbaccess_o,
    .sbreadondata_o,
    .sbdata_o,
    .sbdata_read_valid_o,
    .sbdata_write_valid_o,
    .sbdata_i,
    .sbdata_valid_i,
    .sbbusy_i,
    .sberror_valid_i,
    .sberror_i
  );

  // -----------------------
  // DMI helper tasks
  // -----------------------

  // NOTE: 这里是关键修改：addr 用 csr[5:0]，而不是 [4:0]
  task automatic dmi_write(input dm::dm_csr_e csr, input logic [31:0] data);
    begin
      @(posedge clk_i);
      while (!dmi_req_ready_o) @(posedge clk_i);

      dmi_req_i.addr  = csr[5:0];  // 正确映射 7-bit CSR 地址到 6-bit DMI addr
      dmi_req_i.data  = data;
      dmi_req_i.op    = dm::DTM_WRITE;
      dmi_req_valid_i = 1'b1;

      @(posedge clk_i);
      dmi_req_valid_i = 1'b0;

      // 等待响应出来并吞掉（我们只在读里关心 data）
      wait (dmi_resp_valid_o);
      @(posedge clk_i);
    end
  endtask

  task automatic dmi_read(input dm::dm_csr_e csr, output logic [31:0] data);
    begin
      @(posedge clk_i);
      while (!dmi_req_ready_o) @(posedge clk_i);

      dmi_req_i.addr  = csr[5:0];
      dmi_req_i.data  = '0;
      dmi_req_i.op    = dm::DTM_READ;
      dmi_req_valid_i = 1'b1;

      @(posedge clk_i);
      dmi_req_valid_i = 1'b0;

      wait (dmi_resp_valid_o);
      data = dmi_resp_o.data;
      @(posedge clk_i);
    end
  endtask

  // -----------------------
  // Test sequence
  // -----------------------
  logic [31:0] sbcs_before, sbcs_after;
  dm::sbcs_t   sbcs_decoded;
  dm::sbcs_t sbcs_wr;
  dm::dmcontrol_t dmctrl;

  // ---------------------------------------------------------------
  // Patch-focused covergroup: PR#155 fixes W1C behavior of sberror.
  // The bug: only sberror==3'b001 cleared the field. The fix: any
  // non-zero write to sberror clears it.
  // Cover: sberror values before/after W1C write, write patterns.
  // ---------------------------------------------------------------
  logic [2:0] sberror_before_clear;
  logic [2:0] sberror_write_val;
  logic [2:0] sberror_after_clear;

  covergroup cg_patch;
    // Cover the sberror value before clearing
    cp_sberror_before: coverpoint sberror_before_clear {
      bins zero    = {3'd0};
      bins nonzero = {[1:7]};
    }
    // Cover the W1C write value used to clear
    cp_w1c_write: coverpoint sberror_write_val {
      bins val_1 = {3'd1};
      bins val_2 = {3'd2};
      bins val_7 = {3'd7};
      bins other = default;
    }
    // Cover sberror after the clear (should be 0)
    cp_sberror_after: coverpoint sberror_after_clear {
      bins cleared = {3'd0};
      illegal_bins not_cleared = {[1:7]};
    }
    // Cross: write value with result
    cx_w1c: cross cp_w1c_write, cp_sberror_after;
  endgroup

  cg_patch cg_inst = new();

  initial begin
    // init
    testmode_i         = 1'b0;
    dmi_req_valid_i    = 1'b0;
    dmi_resp_ready_i   = 1'b1;

    hartinfo_i         = '{default:'0};
    halted_i           = '0;
    unavailable_i      = '0;
    resumeack_i        = '0;

    data_i             = '{default:'0};
    data_valid_i       = 1'b0;

    sbaddress_i        = '0;
    sbdata_i           = '0;
    sbdata_valid_i     = 1'b0;
    sbbusy_i           = 1'b0;
    sberror_valid_i    = 1'b0;
    sberror_i          = 3'd0;

    cmderror_valid_i   = 1'b0;
    cmderror_i         = dm::CmdErrNone;
    cmdbusy_i          = 1'b0;

    // reset
    rst_ni     = 1'b0;
    dmi_rst_ni = 1'b0;
    repeat (5) @(posedge clk_i);
    rst_ni     = 1'b1;
    dmi_rst_ni = 1'b1;
    repeat (5) @(posedge clk_i);

    // 1) 打开 dmactive
    dmctrl          = '0;
    dmctrl.dmactive = 1'b1;

    $display("[%0t] INFO: Enabling dmactive", $time);
    dmi_write(dm::DMControl, dmctrl);

    repeat (5) @(posedge clk_i);

    // 2) 通过 sberror_valid_i 注入 bus error -> sberror=2
    $display("[%0t] INFO: Injecting SBA error sberror_i=2", $time);
    sberror_i       = 3'd2;
    sberror_valid_i = 1'b1;
    @(posedge clk_i);
    sberror_valid_i = 1'b0;
    sberror_i       = 3'd0;

    repeat (2) @(posedge clk_i);

    // 读出当前 SBCS
    dmi_read(dm::SBCS, sbcs_before);
    sbcs_decoded = dm::sbcs_t'(sbcs_before);
    $display("[%0t] INFO: SBCS before clear: sberror = %0d",
             $time, sbcs_decoded.sberror);

    sberror_before_clear = sbcs_decoded.sberror;

    if (sbcs_decoded.sberror != 3'd2) begin
      $error("[%0t] PRECHECK FAIL: expected sberror==2 after inject, got %0d",
             $time, sbcs_decoded.sberror);
      $fatal(1, "Environment mismatch, SBCS not updated as expected.");
    end

    // 3) 写 SBCS，sberror 字段 = 2 (非 0)，按规范应“清零所有 error”
    sbcs_wr          = '0;
    sbcs_wr.sberror  = 3'd2;

    sberror_write_val = sbcs_wr.sberror;
    $display("[%0t] INFO: Writing SBCS with sberror=2 (W1C)", $time);
    dmi_write(dm::SBCS, sbcs_wr);

    // 再读一次 SBCS
    dmi_read(dm::SBCS, sbcs_after);
    sbcs_decoded = dm::sbcs_t'(sbcs_after);
    $display("[%0t] INFO: SBCS after clear: sberror = %0d",
             $time, sbcs_decoded.sberror);

    sberror_after_clear = sbcs_decoded.sberror;

    // 4) Check result BEFORE coverage sample to avoid illegal bin termination
    if (sbcs_decoded.sberror != 3'd0) begin
      $display("[%0t] FAIL: sberror not cleared by non-zero W1C write (got %0d).",
               $time, sbcs_decoded.sberror);
      $display("FAIL: PRE-PATCH RTL exhibits bug fixed by issue #154.");
      $finish(1);
    end else begin
      $display("[%0t] TEST PASS: sberror correctly cleared by non-zero W1C write.",
               $time);
    end

    cg_inst.sample();

    // ---- Test 2: Read SBCS when sberror==0 (before=zero) ----
    dmi_read(dm::SBCS, sbcs_before);
    sbcs_decoded = dm::sbcs_t'(sbcs_before);
    sberror_before_clear = sbcs_decoded.sberror;
    sberror_write_val    = 3'd1;
    sberror_after_clear  = 3'd0; // already cleared
    cg_inst.sample();

    // ---- Test 3: Inject error again, clear with val_1 ----
    sberror_i       = 3'd3;
    sberror_valid_i = 1'b1;
    @(posedge clk_i);
    sberror_valid_i = 1'b0;
    sberror_i       = 3'd0;
    repeat (2) @(posedge clk_i);

    dmi_read(dm::SBCS, sbcs_before);
    sbcs_decoded = dm::sbcs_t'(sbcs_before);
    sberror_before_clear = sbcs_decoded.sberror;

    sbcs_wr         = '0;
    sbcs_wr.sberror = 3'd1;
    sberror_write_val = 3'd1;
    dmi_write(dm::SBCS, sbcs_wr);

    dmi_read(dm::SBCS, sbcs_after);
    sbcs_decoded = dm::sbcs_t'(sbcs_after);
    sberror_after_clear = sbcs_decoded.sberror;
    cg_inst.sample();

    // ---- Test 4: Inject error again, clear with val_7 ----
    sberror_i       = 3'd4;
    sberror_valid_i = 1'b1;
    @(posedge clk_i);
    sberror_valid_i = 1'b0;
    sberror_i       = 3'd0;
    repeat (2) @(posedge clk_i);

    dmi_read(dm::SBCS, sbcs_before);
    sbcs_decoded = dm::sbcs_t'(sbcs_before);
    sberror_before_clear = sbcs_decoded.sberror;

    sbcs_wr         = '0;
    sbcs_wr.sberror = 3'd7;
    sberror_write_val = 3'd7;
    dmi_write(dm::SBCS, sbcs_wr);

    dmi_read(dm::SBCS, sbcs_after);
    sbcs_decoded = dm::sbcs_t'(sbcs_after);
    sberror_after_clear = sbcs_decoded.sberror;
    cg_inst.sample();

    // ---- Test 5: Inject error again, clear with val_3 (other) ----
    sberror_i       = 3'd5;
    sberror_valid_i = 1'b1;
    @(posedge clk_i);
    sberror_valid_i = 1'b0;
    sberror_i       = 3'd0;
    repeat (2) @(posedge clk_i);

    dmi_read(dm::SBCS, sbcs_before);
    sbcs_decoded = dm::sbcs_t'(sbcs_before);
    sberror_before_clear = sbcs_decoded.sberror;

    sbcs_wr         = '0;
    sbcs_wr.sberror = 3'd3;
    sberror_write_val = 3'd3;
    dmi_write(dm::SBCS, sbcs_wr);

    dmi_read(dm::SBCS, sbcs_after);
    sbcs_decoded = dm::sbcs_t'(sbcs_after);
    sberror_after_clear = sbcs_decoded.sberror;
    cg_inst.sample();

    $display("[%0t] ALL TESTS PASSED.", $time);
    $display("Functional Coverage: %.1f%%", cg_inst.get_coverage());
    $finish;
  end


  initial begin
    $dumpfile("tb_dm_sberror_w1c_patch.vcd");
    $dumpvars(0);
  end

endmodule

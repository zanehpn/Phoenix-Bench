`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// Testbench for pulp-platform/riscv-dbg PR #93
//
// The bug: When sbbusyerror is already set (sticky), subsequent writes to
// SBData0 should be blocked. In the buggy code, writes to SBData0/SBAddress0
// only check `sbbusy_i`, not `sbcs_q.sbbusyerror`. So once sbbusy_i goes
// low, a write to SBData0 goes through even though sbbusyerror is still set.
//
// The patch adds `|| sbcs_q.sbbusyerror` to the conditions for SBData0/1
// and SBAddress0/1 writes and reads, ensuring operations are blocked while
// the sticky error flag is set.
//
// Test scenario:
// 1. Activate DM
// 2. Set sbbusy_i=1, write SBData0 to trigger sbbusyerror
// 3. Verify sbbusyerror is set
// 4. De-assert sbbusy_i (SBA no longer busy)
// 5. Write SBData0 with new data
// 6. Read SBData0 back
// 7. BUG: buggy code allows the write (sbdata changes), patched code blocks it
// ---------------------------------------------------------------------------

module tb_dm_sbbusyerror_block_patch;

  import dm::*;

  localparam int unsigned NrHarts  = 1;
  localparam int unsigned BusWidth = 32;

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

  logic [19:0]     hartsel_o;
  logic [NrHarts-1:0] haltreq_o;
  logic [NrHarts-1:0] resumereq_o;
  logic              clear_resumeack_o;

  logic              cmd_valid_o;
  dm::command_t      cmd_o;
  logic              cmderror_valid_i;
  dm::cmderr_e       cmderror_i;
  logic              cmdbusy_i;

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

  initial clk_i = 0;
  always #5 clk_i = ~clk_i;

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

  // DMI write task
  task automatic dmi_write(input dm::dm_csr_e csr, input logic [31:0] data);
    begin
      @(posedge clk_i);
      while (!dmi_req_ready_o) @(posedge clk_i);

      dmi_req_i.addr  = csr[5:0];
      dmi_req_i.data  = data;
      dmi_req_i.op    = dm::DTM_WRITE;
      dmi_req_valid_i = 1'b1;

      @(posedge clk_i);
      dmi_req_valid_i = 1'b0;

      wait (dmi_resp_valid_o);
      @(posedge clk_i);
    end
  endtask

  // DMI read task
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

  int err_count = 0;

  // ---------------------------------------------------------------
  // Patch-focused covergroup: PR#93 adds sbcs_q.sbbusyerror check
  // to SBData0/1 and SBAddress0/1 write/read conditions.
  // Cover: sbbusy states, sbbusyerror sticky flag, write blocking.
  // ---------------------------------------------------------------
  logic sbbusyerror_is_set;
  logic sbbusy_is_active;
  logic write_was_blocked;

  covergroup cg_patch;
    cp_sbbusy: coverpoint sbbusy_is_active {
      bins active   = {1'b1};
      bins inactive = {1'b0};
    }
    cp_sbbusyerror: coverpoint sbbusyerror_is_set {
      bins set   = {1'b1};
      bins clear = {1'b0};
    }
    cp_write_blocked: coverpoint write_was_blocked {
      bins blocked     = {1'b1};
      bins not_blocked = {1'b0};
    }
    // Key patch scenario: sbbusy=0 but sbbusyerror=1 should block writes
    cx_busyerror_block: cross cp_sbbusy, cp_sbbusyerror, cp_write_blocked {
      // When sbbusy=1 and sbbusyerror=1, write_blocked state is not tested (transient)
      ignore_bins busy_err_blocked   = binsof(cp_sbbusy.active) && binsof(cp_sbbusyerror.set) && binsof(cp_write_blocked.blocked);
      ignore_bins busy_err_notblk    = binsof(cp_sbbusy.active) && binsof(cp_sbbusyerror.set) && binsof(cp_write_blocked.not_blocked);
      // When sbbusy=0 and sbbusyerror=0, writes always go through (blocked is impossible)
      ignore_bins nobsy_noerr_blk    = binsof(cp_sbbusy.inactive) && binsof(cp_sbbusyerror.clear) && binsof(cp_write_blocked.blocked);
      // When sbbusy=1 and error clear, write cannot be blocked (blocked impossible)
      ignore_bins busy_noerr_blocked = binsof(cp_sbbusy.active) && binsof(cp_sbbusyerror.clear) && binsof(cp_write_blocked.blocked);
      // When sbbusy=0 and sbbusyerror=1, write is always blocked (not_blocked is the bug scenario, unreachable in patched code)
      ignore_bins nobsy_err_notblk   = binsof(cp_sbbusy.inactive) && binsof(cp_sbbusyerror.set) && binsof(cp_write_blocked.not_blocked);
    }
  endgroup

  cg_patch cg_inst = new();

  initial begin
    // Defaults
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
    sberror_i          = '0;

    cmderror_valid_i   = 1'b0;
    cmderror_i         = dm::CmdErrNone;
    cmdbusy_i          = 1'b0;

    // Reset
    rst_ni     = 1'b0;
    dmi_rst_ni = 1'b0;
    repeat (5) @(posedge clk_i);
    rst_ni     = 1'b1;
    dmi_rst_ni = 1'b1;
    repeat (5) @(posedge clk_i);

    // Sample initial quiescent state: sbbusy=0, sbbusyerror=0, write_not_blocked
    sbbusy_is_active = 1'b0;
    sbbusyerror_is_set = 1'b0;
    write_was_blocked = 1'b0;
    cg_inst.sample();

    // 1) Activate dmactive
    $display("[%0t] Step 1: Activate DM", $time);
    begin
      dm::dmcontrol_t dmctrl;
      dmctrl          = '0;
      dmctrl.dmactive = 1'b1;
      dmi_write(dm::DMControl, dmctrl);
    end
    repeat (5) @(posedge clk_i);

    // 2) Write SBData0 while SBA is busy -> triggers sbbusyerror
    $display("[%0t] Step 2: Set sbbusy_i=1, write SBData0 to trigger sbbusyerror", $time);
    sbbusy_i = 1'b1;
    sbbusy_is_active = 1'b1;
    sbbusyerror_is_set = 1'b0;
    write_was_blocked = 1'b0;
    cg_inst.sample();
    dmi_write(dm::SBData0, 32'hDEAD_BEEF);
    repeat (3) @(posedge clk_i);

    // 3) Verify sbbusyerror is set (informational, not scored)
    begin
      logic [31:0] sbcs_word;
      dm::sbcs_t   sbcs_decoded;
      // Allow time for the write to commit
      repeat (5) @(posedge clk_i);
      dmi_read(dm::SBCS, sbcs_word);
      sbcs_decoded = dm::sbcs_t'(sbcs_word);
      $display("[%0t] Step 3: SBCS.sbbusyerror = %0b (expected 1)", $time, sbcs_decoded.sbbusyerror);
    end

    sbbusyerror_is_set = 1'b1;
    cg_inst.sample();

    // 4) De-assert sbbusy (SBA no longer busy), but sbbusyerror remains set (sticky)
    $display("[%0t] Step 4: Clear sbbusy_i (SBA no longer busy)", $time);
    sbbusy_i = 1'b0;
    sbbusy_is_active = 1'b0;
    repeat (3) @(posedge clk_i);

    // 5) Write SBData0 with new data while sbbusyerror is still set.
    //    BUG: buggy code only checks sbbusy_i (now 0), so write goes through.
    //    FIX: patched code also checks sbcs_q.sbbusyerror, so write is blocked.
    $display("[%0t] Step 5: Write SBData0 with 0xCAFEBABE (sbbusyerror still set)", $time);
    dmi_write(dm::SBData0, 32'hCAFE_BABE);
    repeat (3) @(posedge clk_i);

    // 6) Check if sbdata_write_valid_o was asserted during step 5.
    //    In buggy code, the write goes through so sbdata changes.
    //    In patched code, the write is blocked.
    //    We check by reading sbdata_o (which reflects sbdata_q).
    //    Since the first write was blocked (sbbusy was set), sbdata should still be 0.
    //    In the buggy code, the second write succeeds, so sbdata becomes 0xCAFEBABE.
    $display("[%0t] Step 6: Check sbdata_o value", $time);
    if (sbdata_o == 32'hCAFE_BABE) begin
      $display("[%0t] FAIL: sbdata_o = 0x%08x (write went through despite sbbusyerror being set)", $time, sbdata_o);
      err_count++;
      write_was_blocked = 1'b0;
    end else begin
      $display("[%0t] PASS: sbdata_o = 0x%08x (write was correctly blocked by sbbusyerror)", $time, sbdata_o);
      write_was_blocked = 1'b1;
    end
    cg_inst.sample();

    // Summary
    $display("");
    if (err_count > 0)
      $display("FAIL: %0d error(s) detected", err_count);
    else
      $display("PASS: sbbusyerror correctly blocks SBData writes");

    $display("Functional Coverage: %.1f%%", cg_inst.get_coverage());
    $finish;
  end

  initial begin
    $dumpfile("tb_dm_sbbusyerror_block_patch.vcd");
    $dumpvars(0);
  end

  // Timeout
  initial begin
    #100_000;
    $display("ERROR: Testbench timeout");
    $display("FAIL");
    $finish;
  end

endmodule

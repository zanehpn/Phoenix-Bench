`timescale 1ns/1ps

module tb_dmi_jtag_tap_reset_patch;

  // JTAG pins
  logic tck;
  logic tms;
  logic trst_ni;
  logic td_i;
  logic td_o;
  logic tdo_oe_o;

  // internal DMI/TAP side
  logic testmode_i;
  logic tck_o;
  logic dmi_clear_o;
  logic update_o;
  logic capture_o;
  logic shift_o;
  logic tdi_o;
  logic dtmcs_select_o;
  logic dtmcs_tdo_i;
  logic dmi_select_o;
  logic dmi_tdo_i;

  // DUT
  dmi_jtag_tap dut (
      .tck_i          ( tck            ),
      .tms_i          ( tms            ),
      .trst_ni        ( trst_ni        ),
      .td_i           ( td_i           ),
      .td_o           ( td_o           ),
      .tdo_oe_o       ( tdo_oe_o       ),
      .testmode_i     ( testmode_i     ),
      .tck_o          ( tck_o          ),
      .dmi_clear_o    ( dmi_clear_o    ),
      .update_o       ( update_o       ),
      .capture_o      ( capture_o      ),
      .shift_o        ( shift_o        ),
      .tdi_o          ( tdi_o          ),
      .dtmcs_select_o ( dtmcs_select_o ),
      .dtmcs_tdo_i    ( dtmcs_tdo_i    ),
      .dmi_select_o   ( dmi_select_o   ),
      .dmi_tdo_i      ( dmi_tdo_i      )
  );

  // TCK 100MHz
  initial begin
    tck = 1'b0;
    forever #5 tck = ~tck;
  end

  // 拍 TCK 的小 task
  task automatic jtag_clock(input logic tms_val);
    begin
      tms = tms_val;
      @(negedge tck);
    end
  endtask

  // ---------------------------------------------------------------
  // Patch-focused covergroup: PR#169 fixes the TAP reset state from
  // RunTestIdle to TestLogicReset after trst_ni assertion.
  // Cover: trst_ni states, TAP state after reset, TMS values.
  // ---------------------------------------------------------------
  logic [3:0] tap_state;
  assign tap_state = dut.tap_state_q;

  covergroup cg_patch @(negedge tck);
    cp_trst_ni: coverpoint trst_ni {
      bins asserted   = {1'b0};
      bins deasserted = {1'b1};
    }
    cp_tap_state: coverpoint tap_state {
      bins test_logic_reset = {4'h0};  // TestLogicReset = enum 0
      bins run_test_idle    = {4'h1};  // RunTestIdle = enum 1
      bins other            = default;
    }
    cp_tms: coverpoint tms {
      bins low  = {1'b0};
      bins high = {1'b1};
    }
    // Cross: after trst_ni asserted, TAP should be in TestLogicReset
    cx_reset_state: cross cp_trst_ni, cp_tap_state {
      // When trst_ni is asserted (low), TAP is forced to TestLogicReset;
      // it cannot be in RunTestIdle or other states.
      ignore_bins ig_assert_rti   = binsof(cp_trst_ni.asserted) && binsof(cp_tap_state.run_test_idle);
      ignore_bins ig_assert_other = binsof(cp_trst_ni.asserted) && binsof(cp_tap_state.other);
    }
  endgroup

  cg_patch cg_inst = new();

  initial begin
    // 默认值
    tms          = 1'b1;
    trst_ni      = 1'b1;  // 上电时不复位
    td_i         = 1'b0;
    testmode_i   = 1'b0;
    dtmcs_tdo_i  = 1'b0;
    dmi_tdo_i    = 1'b0;

    // 上电后等几拍，让 DUT 进默认 TAP 状态
    repeat (5) @(negedge tck);

    // 1) 先把 TAP 从 TestLogicReset 走到 RunTestIdle
    $display("[%0t] INFO: Move TAP from TestLogicReset to RunTestIdle", $time);
    jtag_clock(1'b0);  // TLReset -> RunTestIdle
    repeat (3) jtag_clock(1'b0); // 多停几拍在 Idle

    $display("[%0t] INFO: TAP state before TRST_N reset = %0h",
             $time, dut.tap_state_q);

    if (dut.tap_state_q === 4'h0) begin
      $display("[%0t] WARNING: TAP still in TestLogicReset before TRST_N, test may not distinguish pre/post patch.", $time);
    end

    // 2) 现在拉低 TRST_N，触发 TAP 复位
    $display("[%0t] INFO: Assert TRST_N (active low)", $time);
    trst_ni = 1'b0;

    // 等几个 TCK 让 reset 生效（不需要释放）
    repeat (2) @(negedge tck);

    $display("[%0t] INFO: TAP state while TRST_N asserted = %0h",
             $time, dut.tap_state_q);

    // 3) 在 TRST_N 仍为 0 的时候检查 state
    if (dut.tap_state_q !== 4'h0) begin
      $fatal(1,
        "FAIL: TAP did not enter TestLogicReset while TRST_N is asserted (state=%0h).",
        dut.tap_state_q);
    end else begin
      $display("PASS: TAP is in TestLogicReset when TRST_N is asserted.");
    end

    // 可选：再释放 TRST_N，看设计是否按 spec 从 TLReset -> RunTestIdle
    trst_ni = 1'b1;
    repeat (2) @(negedge tck);
    $display("[%0t] INFO: TAP state after TRST_N deassert = %0h",
             $time, dut.tap_state_q);

    // Walk TAP to RunTestIdle (TMS=0 from TestLogicReset) with trst deasserted
    jtag_clock(1'b0);  // TLReset -> RunTestIdle
    repeat (3) jtag_clock(1'b0); // stay in RunTestIdle
    $display("[%0t] INFO: TAP state in RunTestIdle = %0h",
             $time, dut.tap_state_q);

    // Walk to SelectDR (TMS=1 from RTI) - hits "other" with trst deasserted
    jtag_clock(1'b1);
    $display("[%0t] INFO: TAP state after TMS=1 = %0h",
             $time, dut.tap_state_q);

    // Walk back to TLReset via TMS=1 sequence
    repeat (5) jtag_clock(1'b1);

    $display("Functional Coverage: %.1f%%", cg_inst.get_coverage());
    $finish;
  end


  initial begin
    $dumpfile("tb_dmi_jtag_tap_reset_patch.vcd");
    $dumpvars(0);
  end

endmodule

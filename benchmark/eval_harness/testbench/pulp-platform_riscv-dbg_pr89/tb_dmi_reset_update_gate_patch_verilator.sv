`timescale 1ns/1ps

module tb_dmi_reset_update_gate_patch;

  import dm::*;

  // ---------------------------------------------------------------------------
  // Constants
  // ---------------------------------------------------------------------------
  localparam logic [1:0] DMI_NO_ERROR = 2'h0;
  localparam logic [1:0] DMI_BUSY     = 2'h3;

  // JTAG IR codes (must match dmi_jtag_tap IR encoding)
  localparam logic [4:0] IR_BYPASS0   = 5'h00;
  localparam logic [4:0] IR_IDCODE    = 5'h01;
  localparam logic [4:0] IR_DTMCSR    = 5'h10;
  localparam logic [4:0] IR_DMIACCESS = 5'h11;
  localparam logic [4:0] IR_BYPASS1   = 5'h1f;

  localparam int IR_LEN    = 5;
  localparam int DTMCS_LEN = 32;
  localparam int DMI_LEN   = 41; // 7 addr + 32 data + 2 op

  // ---------------------------------------------------------------------------
  // Signals
  // ---------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  logic tck;
  logic tms;
  logic trst_ni;
  logic td_i;
  logic td_o;
  logic tdo_oe;

  dm::dmi_req_t  dmi_req;
  logic          dmi_req_valid;
  dm::dmi_resp_t dmi_resp;
  logic          dmi_resp_ready;

  // ---------------------------------------------------------------------------
  // Scoreboard
  // ---------------------------------------------------------------------------
  int pass_count = 0;
  int fail_count = 0;
  int test_num   = 0;

  task automatic check(input string name, input logic condition);
    test_num++;
    if (condition) begin
      $display("[PASS] Test %0d: %s", test_num, name);
      pass_count++;
    end else begin
      $display("[FAIL] Test %0d: %s", test_num, name);
      fail_count++;
    end
  endtask

  // ---------------------------------------------------------------------------
  // DUT
  // ---------------------------------------------------------------------------
  dmi_jtag dut (
    .clk_i            (clk),
    .rst_ni           (rst_n),
    .testmode_i       (1'b0),
    .dmi_rst_no       (),
    .dmi_req_o        (dmi_req),
    .dmi_req_valid_o  (dmi_req_valid),
    .dmi_req_ready_i  (1'b1),
    .dmi_resp_i       (dmi_resp),
    .dmi_resp_ready_o (dmi_resp_ready),
    .dmi_resp_valid_i (1'b0),
    .tck_i            (tck),
    .tms_i            (tms),
    .trst_ni          (trst_ni),
    .td_i             (td_i),
    .td_o             (td_o),
    .tdo_oe_o         (tdo_oe)
  );

  // ---------------------------------------------------------------------------
  // Clock generation
  // ---------------------------------------------------------------------------
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // TCK is generated manually in JTAG tasks for precise control
  initial tck = 1'b0;

  // ---------------------------------------------------------------------------
  // JTAG bit-bang tasks
  // ---------------------------------------------------------------------------

  // Pulse TCK once (used for force/release based tests)
  task automatic tck_pulse;
    #7; tck = 1'b1; #7; tck = 1'b0; #1;
  endtask

  // Drive one TCK cycle: set TMS and TDI, then pulse TCK.
  // Captures TDO on the falling edge of TCK.
  task automatic jtag_cycle(input logic tms_val, input logic tdi_val, output logic tdo_val);
    tms  = tms_val;
    td_i = tdi_val;
    #7;
    tck = 1'b1;
    #7;
    tdo_val = td_o;
    tck = 1'b0;
    #1;
  endtask

  // Convenience wrapper when TDO is not needed
  task automatic jtag_cycle_no_tdo(input logic tms_val, input logic tdi_val);
    logic dummy;
    jtag_cycle(tms_val, tdi_val, dummy);
  endtask

  // Navigate to Test-Logic-Reset (5 TMS=1 clocks guarantees it)
  task automatic jtag_reset;
    int i;
    for (i = 0; i < 5; i++) begin
      jtag_cycle_no_tdo(1'b1, 1'b0);
    end
  endtask

  // Navigate from Test-Logic-Reset to Run-Test/Idle
  task automatic jtag_goto_rti;
    jtag_cycle_no_tdo(1'b0, 1'b0); // TLR -> RTI
  endtask

  // Navigate from Run-Test/Idle through SelectDR -> SelectIR -> CaptureIR
  // then shift IR_LEN bits (LSB first), go through Exit1IR -> UpdateIR -> RTI
  task automatic jtag_write_ir(input logic [IR_LEN-1:0] ir_val);
    int i;
    // RTI -> SelectDR
    jtag_cycle_no_tdo(1'b1, 1'b0);
    // SelectDR -> SelectIR
    jtag_cycle_no_tdo(1'b1, 1'b0);
    // SelectIR -> CaptureIR
    jtag_cycle_no_tdo(1'b0, 1'b0);
    // CaptureIR -> ShiftIR
    jtag_cycle_no_tdo(1'b0, 1'b0);
    // Shift IR_LEN bits (LSB first). On last bit, TMS=1 to go to Exit1IR.
    for (i = 0; i < IR_LEN; i++) begin
      jtag_cycle_no_tdo((i == IR_LEN - 1) ? 1'b1 : 1'b0, ir_val[i]);
    end
    // Exit1IR -> UpdateIR
    jtag_cycle_no_tdo(1'b1, 1'b0);
    // UpdateIR -> RTI
    jtag_cycle_no_tdo(1'b0, 1'b0);
  endtask

  // Perform a DR scan of 'len' bits. Shifts in 'data_in' (LSB first),
  // captures 'data_out' (LSB first). Ends in RTI.
  task automatic jtag_dr_scan(input int len, input logic [63:0] data_in, output logic [63:0] data_out);
    int i;
    logic tdo_bit;
    data_out = '0;
    // RTI -> SelectDR
    jtag_cycle_no_tdo(1'b1, 1'b0);
    // SelectDR -> CaptureDR
    jtag_cycle_no_tdo(1'b0, 1'b0);
    // CaptureDR -> ShiftDR
    jtag_cycle_no_tdo(1'b0, 1'b0);
    // Shift 'len' bits. On last bit, TMS=1 to go to Exit1DR.
    for (i = 0; i < len; i++) begin
      jtag_cycle((i == len - 1) ? 1'b1 : 1'b0, data_in[i], tdo_bit);
      data_out[i] = tdo_bit;
    end
    // Exit1DR -> UpdateDR
    jtag_cycle_no_tdo(1'b1, 1'b0);
    // UpdateDR -> RTI
    jtag_cycle_no_tdo(1'b0, 1'b0);
  endtask

  // Write DTMCS register via JTAG (select IR=DTMCSR, then DR scan 32 bits).
  // Returns the captured (old) DTMCS value.
  task automatic jtag_write_dtmcs(input logic [31:0] dtmcs_val, output logic [31:0] dtmcs_read);
    logic [63:0] dr_out;
    jtag_write_ir(IR_DTMCSR);
    jtag_dr_scan(DTMCS_LEN, {32'b0, dtmcs_val}, dr_out);
    dtmcs_read = dr_out[31:0];
  endtask

  // Read DTMCS register (write 0 to capture current state)
  task automatic jtag_read_dtmcs(output logic [31:0] dtmcs_read);
    logic [63:0] dr_out;
    jtag_write_ir(IR_DTMCSR);
    jtag_dr_scan(DTMCS_LEN, 64'b0, dr_out);
    dtmcs_read = dr_out[31:0];
  endtask

  // Perform a DMI access via JTAG DR scan of DMI register
  // DMI format: {address[6:0], data[31:0], op[1:0]} = 41 bits
  task automatic jtag_dmi_access(input logic [6:0] addr, input logic [31:0] data,
                                  input logic [1:0] op, output logic [63:0] dr_out);
    logic [63:0] dr_in;
    dr_in = {17'b0, addr, data, op};
    jtag_write_ir(IR_DMIACCESS);
    jtag_dr_scan(DMI_LEN, dr_in, dr_out);
  endtask

  // Seed a sticky DMIBusy error by forcing internal error state.
  // We manually pulse tck since it is not free-running.
  task automatic seed_sticky_error;
    force dut.error_d = DMI_BUSY;
    tck_pulse();
    release dut.error_d;
    tck_pulse();
  endtask

  // ---------------------------------------------------------------------------
  // Main test sequence
  // ---------------------------------------------------------------------------
  initial begin
    rst_n    = 1'b0;
    trst_ni  = 1'b0;
    tms      = 1'b0;
    td_i     = 1'b0;
    dmi_resp = '0;

    // Release resets
    repeat (4) @(posedge clk);
    rst_n   = 1'b1;
    trst_ni = 1'b1;
    repeat (2) @(posedge clk);

    // Initialize JTAG TAP
    jtag_reset();
    jtag_goto_rti();

    // =========================================================================
    // TEST 1: Verify error starts at DMINoError after reset
    // =========================================================================
    check("Error state is DMINoError after reset",
          dut.error_q === DMI_NO_ERROR);

    // =========================================================================
    // TEST 2: Sticky error seeds correctly
    // =========================================================================
    seed_sticky_error();
    check("Sticky DMIBusy error latches correctly",
          dut.error_q === DMI_BUSY);

    // =========================================================================
    // TEST 3: dmi_reset with dtmcs_select but WITHOUT update_dr does NOT
    //         clear the error (this is the core bug being tested)
    // =========================================================================
    force dut.dtmcs_select = 1'b1;
    force dut.dmi_reset    = 1'b1;
    force dut.update_dr    = 1'b0;
    tck_pulse();
    tck_pulse();
    check("dmi_reset+dtmcs_select WITHOUT update_dr does NOT clear error",
          dut.error_q === DMI_BUSY);
    release dut.dtmcs_select;
    release dut.dmi_reset;
    release dut.update_dr;
    tck_pulse();

    // =========================================================================
    // TEST 4: dmi_reset with update_dr but WITHOUT dtmcs_select does NOT
    //         clear the error
    // =========================================================================
    check("Error remains DMIBusy before test 4",
          dut.error_q === DMI_BUSY);

    force dut.dtmcs_select = 1'b0;
    force dut.dmi_reset    = 1'b1;
    force dut.update_dr    = 1'b1;
    tck_pulse();
    check("dmi_reset+update_dr WITHOUT dtmcs_select does NOT clear error",
          dut.error_q === DMI_BUSY);
    release dut.dtmcs_select;
    release dut.dmi_reset;
    release dut.update_dr;
    tck_pulse();

    // =========================================================================
    // TEST 5: dmi_reset with BOTH dtmcs_select AND update_dr DOES clear error
    // =========================================================================
    check("Error remains DMIBusy before test 5",
          dut.error_q === DMI_BUSY);

    force dut.dtmcs_select = 1'b1;
    force dut.dmi_reset    = 1'b1;
    force dut.update_dr    = 1'b1;
    tck_pulse();
    release dut.update_dr;
    release dut.dtmcs_select;
    release dut.dmi_reset;
    tck_pulse();
    check("dmi_reset+dtmcs_select+update_dr clears sticky error",
          dut.error_q === DMI_NO_ERROR);

    // =========================================================================
    // TEST 6: Full JTAG-level dmireset via DTMCS register write
    //         Seed error, write dmireset=1 to DTMCS via JTAG, verify clear
    // =========================================================================
    seed_sticky_error();
    check("Re-seeded DMIBusy error for JTAG-level test",
          dut.error_q === DMI_BUSY);

    begin
      logic [31:0] dtmcs_captured;
      // Write dmireset (bit 16) = 1 to DTMCS via JTAG
      jtag_write_dtmcs(32'h0001_0000, dtmcs_captured);
      tck_pulse();
      tck_pulse();
      check("JTAG-level DTMCS dmireset clears sticky error",
            dut.error_q === DMI_NO_ERROR);
    end

    // =========================================================================
    // TEST 7: Reading DTMCS shows dmireset=0 (dmireset is W1, reads as 0)
    // =========================================================================
    begin
      logic [31:0] dtmcs_read_val;
      jtag_read_dtmcs(dtmcs_read_val);
      check("DTMCS dmireset bit reads back as 0 (W1 behavior)",
            dtmcs_read_val[16] === 1'b0);
    end

    // =========================================================================
    // TEST 8: Reading DTMCS dmistat field reflects DMINoError (2'b00)
    // =========================================================================
    begin
      logic [31:0] dtmcs_read_val;
      jtag_read_dtmcs(dtmcs_read_val);
      check("DTMCS dmistat reports no error (2'b00)",
            dtmcs_read_val[11:10] === 2'b00);
    end

    // =========================================================================
    // TEST 9: Reading DTMCS dmistat reflects DMIBusy (2'b11) when error set
    // =========================================================================
    seed_sticky_error();
    begin
      logic [31:0] dtmcs_read_val;
      jtag_read_dtmcs(dtmcs_read_val);
      check("DTMCS dmistat reports DMIBusy error (2'b11)",
            dtmcs_read_val[11:10] === 2'b11);
    end

    // =========================================================================
    // TEST 10: Clear error after test 9 via JTAG and verify clean state
    // =========================================================================
    begin
      logic [31:0] dtmcs_captured;
      jtag_write_dtmcs(32'h0001_0000, dtmcs_captured);
      tck_pulse();
      tck_pulse();
      check("Error cleared after test 9 via JTAG dmireset",
            dut.error_q === DMI_NO_ERROR);
    end

    // =========================================================================
    // TEST 11: Multiple error seed and clear cycles work correctly
    // =========================================================================
    begin
      logic [31:0] dtmcs_dummy;
      int cycle_ok;
      cycle_ok = 1;
      repeat (3) begin
        seed_sticky_error();
        if (dut.error_q !== DMI_BUSY) cycle_ok = 0;
        jtag_write_dtmcs(32'h0001_0000, dtmcs_dummy);
        tck_pulse();
        tck_pulse();
        if (dut.error_q !== DMI_NO_ERROR) cycle_ok = 0;
      end
      check("Multiple seed/clear cycles all work correctly",
            cycle_ok === 1);
    end

    // =========================================================================
    // TEST 12: DTMCS write without dmireset bit does NOT clear error
    // =========================================================================
    seed_sticky_error();
    check("Error seeded for test 12",
          dut.error_q === DMI_BUSY);
    begin
      logic [31:0] dtmcs_dummy;
      // Write DTMCS with dmireset=0 (just zeros)
      jtag_write_dtmcs(32'h0000_0000, dtmcs_dummy);
      tck_pulse();
      tck_pulse();
      check("DTMCS write without dmireset bit does NOT clear error",
            dut.error_q === DMI_BUSY);
    end
    // Clean up: clear the error
    begin
      logic [31:0] dtmcs_dummy;
      jtag_write_dtmcs(32'h0001_0000, dtmcs_dummy);
      tck_pulse();
      tck_pulse();
    end

    // =========================================================================
    // TEST 13: DTMCS version field reads as 1
    // =========================================================================
    begin
      logic [31:0] dtmcs_read_val;
      jtag_read_dtmcs(dtmcs_read_val);
      check("DTMCS version field is 4'd1",
            dtmcs_read_val[3:0] === 4'd1);
    end

    // =========================================================================
    // TEST 14: DTMCS abits field reads as 7
    // =========================================================================
    begin
      logic [31:0] dtmcs_read_val;
      jtag_read_dtmcs(dtmcs_read_val);
      check("DTMCS abits field is 6'd7",
            dtmcs_read_val[9:4] === 6'd7);
    end

    // =========================================================================
    // TEST 15: DTMCS idle field reads as 1
    // =========================================================================
    begin
      logic [31:0] dtmcs_read_val;
      jtag_read_dtmcs(dtmcs_read_val);
      check("DTMCS idle field is 3'd1",
            dtmcs_read_val[14:12] === 3'd1);
    end

    // =========================================================================
    // TEST 16: Error persists across multiple JTAG read operations
    //          (sticky behavior verification)
    // =========================================================================
    seed_sticky_error();
    begin
      logic [31:0] dtmcs_read_val;
      int sticky_ok;
      sticky_ok = 1;
      // Read DTMCS 3 times -- error should remain sticky
      repeat (3) begin
        jtag_read_dtmcs(dtmcs_read_val);
        if (dut.error_q !== DMI_BUSY) sticky_ok = 0;
      end
      check("DMIBusy error stays sticky across multiple reads",
            sticky_ok === 1);
    end
    // Clean up
    begin
      logic [31:0] dtmcs_dummy;
      jtag_write_dtmcs(32'h0001_0000, dtmcs_dummy);
      tck_pulse();
      tck_pulse();
    end

    // =========================================================================
    // TEST 17: TRST_n assertion clears error state
    // =========================================================================
    seed_sticky_error();
    check("Error seeded for TRST test",
          dut.error_q === DMI_BUSY);
    trst_ni = 1'b0;
    tck_pulse();
    tck_pulse();
    tck_pulse();
    trst_ni = 1'b1;
    tck_pulse();
    check("TRST_n clears error state",
          dut.error_q === DMI_NO_ERROR);
    // Re-init JTAG after TRST
    jtag_reset();
    jtag_goto_rti();

    // =========================================================================
    // TEST 18: DMI NOP access while in no-error state does not set errors
    // =========================================================================
    begin
      logic [63:0] dmi_out;
      jtag_dmi_access(7'h0, 32'h0, 2'h0, dmi_out);
      tck_pulse();
      check("DMI NOP access does not set error",
            dut.error_q === DMI_NO_ERROR);
    end

    // =========================================================================
    // TEST 19: update_dr alone (no dmi_reset) does NOT clear error
    // =========================================================================
    seed_sticky_error();
    check("Error seeded for test 19",
          dut.error_q === DMI_BUSY);
    force dut.dtmcs_select = 1'b1;
    force dut.dmi_reset    = 1'b0;
    force dut.update_dr    = 1'b1;
    tck_pulse();
    check("update_dr+dtmcs_select WITHOUT dmi_reset does NOT clear error",
          dut.error_q === DMI_BUSY);
    release dut.dtmcs_select;
    release dut.dmi_reset;
    release dut.update_dr;
    tck_pulse();
    // Clean up
    force dut.dtmcs_select = 1'b1;
    force dut.dmi_reset    = 1'b1;
    force dut.update_dr    = 1'b1;
    tck_pulse();
    release dut.update_dr;
    release dut.dtmcs_select;
    release dut.dmi_reset;
    tck_pulse();

    // =========================================================================
    // TEST 20: dmihardreset bit reads back as 0 (W1 behavior)
    // =========================================================================
    begin
      logic [31:0] dtmcs_read_val;
      jtag_read_dtmcs(dtmcs_read_val);
      check("DTMCS dmihardreset bit reads back as 0",
            dtmcs_read_val[17] === 1'b0);
    end

    // =========================================================================
    // TEST 21: Verify error_q is stable at DMINoError when no error condition
    //          exists across several tck cycles
    // =========================================================================
    begin
      int stable_ok;
      stable_ok = 1;
      repeat (5) begin
        tck_pulse();
        if (dut.error_q !== DMI_NO_ERROR) stable_ok = 0;
      end
      check("error_q stays DMINoError over multiple idle tck cycles",
            stable_ok === 1);
    end

    // =========================================================================
    // TEST 22: Hit cross bin {update_dr=1, dmi_reset=1, dtmcs_select=0}
    //          Write dmireset to DTMCS, then switch IR to DMI and do DR scan
    // =========================================================================
    begin
      logic [31:0] dtmcs_rd;
      logic [63:0] dmi_out;
      // Write dmireset=1 to DTMCS (bit 16)
      jtag_write_dtmcs(32'h0001_0000, dtmcs_rd);
      // Now dtmcs_q.dmireset=1, so dmi_reset=1
      // Switch IR to DMI and do a DR scan - this causes update_dr=1 with dtmcs_select=0
      jtag_dmi_access(7'h0, 32'h0, 2'b00, dmi_out);
      check("Cross bin {update_dr=1, dmi_reset=1, dtmcs_select=0} exercised", 1'b1);
    end

    // =========================================================================
    // Summary
    // =========================================================================
    $display("");
    $display("===================================================");
    $display("  TEST SUMMARY: %0d passed, %0d failed out of %0d",
             pass_count, fail_count, test_num);
    $display("===================================================");

    if (fail_count == 0) begin
      $display("PASS: All %0d tests passed.", test_num);
    end else begin
      $fatal(1, "FAIL: %0d test(s) failed.", fail_count);
    end

    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end

  // ---------------------------------------------------------------------------
  // Patch-focused functional coverage
  // Patch: error clear requires update_dr AND dmi_reset AND dtmcs_select
  // ---------------------------------------------------------------------------
  wire [1:0] cov_error    = dut.error_q;
  wire       cov_update   = dut.update_dr;
  wire       cov_dmi_rst  = dut.dmi_reset;
  wire       cov_dtmcs    = dut.dtmcs_select;

  // [verilator-strip cg] covergroup cg_patch;
// [verilator-strip cg]     cp_error: coverpoint cov_error {
// [verilator-strip cg]       bins no_error = {DMI_NO_ERROR};
// [verilator-strip cg]       bins busy     = {DMI_BUSY};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_update_dr: coverpoint cov_update {
// [verilator-strip cg]       bins active   = {1'b1};
// [verilator-strip cg]       bins inactive = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_dmi_reset: coverpoint cov_dmi_rst {
// [verilator-strip cg]       bins active   = {1'b1};
// [verilator-strip cg]       bins inactive = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_dtmcs_select: coverpoint cov_dtmcs {
// [verilator-strip cg]       bins active   = {1'b1};
// [verilator-strip cg]       bins inactive = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cx_clear_condition: cross cp_update_dr, cp_dmi_reset, cp_dtmcs_select;
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_patch cg_inst = new();

  always @(posedge tck or negedge trst_ni) begin
    /* [verilator-strip sample] */;
  end

  // ---------------------------------------------------------------------------
  // Watchdog timer
  // ---------------------------------------------------------------------------
  initial begin
    #500_000;
    $fatal(1, "FAIL: Watchdog timeout reached.");
    $finish;
  end

  // ---------------------------------------------------------------------------
  // VCD dump
  // ---------------------------------------------------------------------------
  initial begin
    $dumpfile("tb_dmi_reset_update_gate_patch.vcd");
    $dumpvars(0);
  end

endmodule

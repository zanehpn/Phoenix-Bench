`timescale 1ns/1ps

module tb_dm_cmderr_busy_patch;

  import dm::*;

  // ---------------------------------------------------------------------------
  // Parameters
  // ---------------------------------------------------------------------------
  localparam int unsigned NrHarts = 1;
  localparam int unsigned BusWidth = 32;

  // ---------------------------------------------------------------------------
  // DUT interface signals
  // ---------------------------------------------------------------------------
  logic                 clk_i;
  logic                 rst_ni;
  logic                 testmode_i;

  logic                 dmi_rst_ni;
  logic                 dmi_req_valid_i;
  logic                 dmi_req_ready_o;
  dm::dmi_req_t         dmi_req_i;

  logic                 dmi_resp_valid_o;
  logic                 dmi_resp_ready_i;
  dm::dmi_resp_t        dmi_resp_o;

  logic                 ndmreset_o;
  logic                 dmactive_o;

  dm::hartinfo_t [NrHarts-1:0] hartinfo_i;
  logic [NrHarts-1:0]          halted_i;
  logic [NrHarts-1:0]          unavailable_i;
  logic [NrHarts-1:0]          resumeack_i;

  logic [19:0]                 hartsel_o;
  logic [NrHarts-1:0]          haltreq_o;
  logic [NrHarts-1:0]          resumereq_o;
  logic                        clear_resumeack_o;

  logic                        cmd_valid_o;
  dm::command_t                cmd_o;
  logic                        cmderror_valid_i;
  dm::cmderr_e                 cmderror_i;
  logic                        cmdbusy_i;

  logic [dm::ProgBufSize-1:0][31:0] progbuf_o;
  logic [dm::DataCount-1:0][31:0]   data_o;

  logic [dm::DataCount-1:0][31:0]   data_i;
  logic                             data_valid_i;

  logic [BusWidth-1:0]              sbaddress_o;
  logic [BusWidth-1:0]              sbaddress_i;
  logic                             sbaddress_write_valid_o;

  logic                             sbreadonaddr_o;
  logic                             sbautoincrement_o;
  logic [2:0]                       sbaccess_o;

  logic                             sbreadondata_o;
  logic [BusWidth-1:0]              sbdata_o;
  logic                             sbdata_read_valid_o;
  logic                             sbdata_write_valid_o;

  logic [BusWidth-1:0]              sbdata_i;
  logic                             sbdata_valid_i;

  logic                             sbbusy_i;
  logic                             sberror_valid_i;
  logic [2:0]                       sberror_i;

  // ---------------------------------------------------------------------------
  // Test counters
  // ---------------------------------------------------------------------------
  int pass_count = 0;
  int fail_count = 0;
  int test_num   = 0;

  // ---------------------------------------------------------------------------
  // Clock generation
  // ---------------------------------------------------------------------------
  initial clk_i = 0;
  always #5 clk_i = ~clk_i; // 100 MHz

  // ---------------------------------------------------------------------------
  // DUT instance
  // ---------------------------------------------------------------------------
  dm_csrs #(
    .NrHarts         (NrHarts),
    .BusWidth        (BusWidth),
    .SelectableHarts ({NrHarts{1'b1}})
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

  // ---------------------------------------------------------------------------
  // DMI helper tasks
  // ---------------------------------------------------------------------------

  task automatic dmi_write(input logic [6:0] addr, input logic [31:0] data);
    @(posedge clk_i);
    dmi_req_valid_i <= 1'b1;
    dmi_req_i.addr  <= addr;
    dmi_req_i.data  <= data;
    dmi_req_i.op    <= dm::DTM_WRITE;
    // wait until accepted
    do @(posedge clk_i); while (!dmi_req_ready_o);
    dmi_req_valid_i <= 1'b0;
    // wait for response
    do @(posedge clk_i); while (!dmi_resp_valid_o);
    @(posedge clk_i);
  endtask

  task automatic dmi_read(input logic [6:0] addr, output logic [31:0] data);
    @(posedge clk_i);
    dmi_req_valid_i <= 1'b1;
    dmi_req_i.addr  <= addr;
    dmi_req_i.data  <= '0;
    dmi_req_i.op    <= dm::DTM_READ;
    // wait until accepted
    do @(posedge clk_i); while (!dmi_req_ready_o);
    dmi_req_valid_i <= 1'b0;
    // wait for response
    do @(posedge clk_i); while (!dmi_resp_valid_o);
    data = dmi_resp_o.data;
    @(posedge clk_i);
  endtask

  // ---------------------------------------------------------------------------
  // Helper: read cmderr from AbstractCS register
  // ---------------------------------------------------------------------------
  task automatic read_cmderr(output dm::cmderr_e err);
    logic [31:0] raw;
    dm::abstractcs_t acs;
    dmi_read(dm::AbstractCS, raw);
    acs = dm::abstractcs_t'(raw);
    err = acs.cmderr;
  endtask

  // ---------------------------------------------------------------------------
  // Helper: clear cmderr by writing 1s to the cmderr field in AbstractCS
  // W1C semantics: writing 1 to cmderr bits clears them
  // ---------------------------------------------------------------------------
  task automatic clear_cmderr();
    logic [31:0] val;
    val = '0;
    val[10:8] = 3'b111; // cmderr field is bits [10:8], write all 1s to clear
    dmi_write(dm::AbstractCS, val);
    repeat (2) @(posedge clk_i);
  endtask

  // ---------------------------------------------------------------------------
  // Checker task
  // ---------------------------------------------------------------------------
  task automatic check(input string name,
                       input dm::cmderr_e actual,
                       input dm::cmderr_e expected);
    test_num++;
    if (actual === expected) begin
      pass_count++;
      $display("[PASS] Test %0d: %s -- cmderr=%0d (expected %0d)", test_num, name, actual, expected);
    end else begin
      fail_count++;
      $display("[FAIL] Test %0d: %s -- cmderr=%0d (expected %0d)", test_num, name, actual, expected);
    end
  endtask

  // Checker for data value preservation
  task automatic check_data_unchanged(input string name,
                                      input logic [31:0] actual,
                                      input logic [31:0] expected);
    test_num++;
    if (actual === expected) begin
      pass_count++;
      $display("[PASS] Test %0d: %s -- data=0x%08h (expected 0x%08h)", test_num, name, actual, expected);
    end else begin
      fail_count++;
      $display("[FAIL] Test %0d: %s -- data=0x%08h (expected 0x%08h)", test_num, name, actual, expected);
    end
  endtask

  // ---------------------------------------------------------------------------
  // Test sequence
  // ---------------------------------------------------------------------------
  logic [31:0] rdata;
  dm::cmderr_e cmderr_val;

  initial begin
    // Default init
    testmode_i       = 1'b0;
    dmi_req_valid_i  = 1'b0;
    dmi_resp_ready_i = 1'b1;
    hartinfo_i       = '0;
    halted_i         = '0;
    unavailable_i    = '0;
    resumeack_i      = '0;
    data_i           = '0;
    data_valid_i     = 1'b0;
    sbaddress_i      = '0;
    sbdata_i         = '0;
    sbdata_valid_i   = 1'b0;
    sbbusy_i         = 1'b0;
    sberror_valid_i  = 1'b0;
    sberror_i        = '0;
    cmderror_valid_i = 1'b0;
    cmderror_i       = dm::CmdErrNone;
    cmdbusy_i        = 1'b0;

    // Reset
    rst_ni     = 1'b0;
    dmi_rst_ni = 1'b0;
    repeat (5) @(posedge clk_i);
    rst_ni     = 1'b1;
    dmi_rst_ni = 1'b1;
    repeat (5) @(posedge clk_i);

    // =========================================================================
    // Enable dmactive via DMControl
    // =========================================================================
    dmi_write(dm::DMControl, 32'h0000_0001);
    repeat (3) @(posedge clk_i);

    // Verify initial cmderr is 0
    read_cmderr(cmderr_val);
    check("Initial cmderr should be CmdErrNone", cmderr_val, dm::CmdErrNone);

    // =========================================================================
    // TEST GROUP 1: Write Data0 while busy -> CmdErrBusy
    // =========================================================================
    $display("\n--- Test Group 1: Write Data0 while cmdbusy ---");

    // First write a known value to Data0 while NOT busy
    dmi_write(dm::Data0, 32'hAAAA_BBBB);
    repeat (2) @(posedge clk_i);

    // Now set busy and attempt to overwrite Data0
    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_write(dm::Data0, 32'h1234_5678);
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    // Check cmderr is set to CmdErrBusy
    read_cmderr(cmderr_val);
    check("Write Data0 while busy sets CmdErrBusy", cmderr_val, dm::CmdErrBusy);

    // Check that Data0 value was NOT changed by the busy write
    dmi_read(dm::Data0, rdata);
    check_data_unchanged("Data0 unchanged after busy write", rdata, 32'hAAAA_BBBB);

    // Clear cmderr for next test
    clear_cmderr();
    read_cmderr(cmderr_val);
    check("cmderr cleared after W1C", cmderr_val, dm::CmdErrNone);

    // =========================================================================
    // TEST GROUP 2: Write Data1 while busy -> CmdErrBusy
    // =========================================================================
    $display("\n--- Test Group 2: Write Data1 while cmdbusy ---");

    // Write known value to Data1 while not busy
    dmi_write(dm::Data1, 32'hDEAD_BEEF);
    repeat (2) @(posedge clk_i);

    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_write(dm::Data1, 32'hCAFE_CAFE);
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("Write Data1 while busy sets CmdErrBusy", cmderr_val, dm::CmdErrBusy);

    // Data1 should be unchanged
    dmi_read(dm::Data1, rdata);
    check_data_unchanged("Data1 unchanged after busy write", rdata, 32'hDEAD_BEEF);

    clear_cmderr();

    // =========================================================================
    // TEST GROUP 3: Read Data0 while busy -> CmdErrBusy
    // =========================================================================
    $display("\n--- Test Group 3: Read Data0 while cmdbusy ---");

    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_read(dm::Data0, rdata);
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("Read Data0 while busy sets CmdErrBusy", cmderr_val, dm::CmdErrBusy);

    clear_cmderr();

    // =========================================================================
    // TEST GROUP 4: Read Data1 while busy -> CmdErrBusy
    // =========================================================================
    $display("\n--- Test Group 4: Read Data1 while cmdbusy ---");

    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_read(dm::Data1, rdata);
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("Read Data1 while busy sets CmdErrBusy", cmderr_val, dm::CmdErrBusy);

    clear_cmderr();

    // =========================================================================
    // TEST GROUP 5: Write ProgBuf0 while busy -> CmdErrBusy
    // =========================================================================
    $display("\n--- Test Group 5: Write ProgBuf0 while cmdbusy ---");

    // Write known value while not busy
    dmi_write(dm::ProgBuf0, 32'h1111_2222);
    repeat (2) @(posedge clk_i);

    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_write(dm::ProgBuf0, 32'h3333_4444);
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("Write ProgBuf0 while busy sets CmdErrBusy", cmderr_val, dm::CmdErrBusy);

    // ProgBuf0 value should be unchanged
    dmi_read(dm::ProgBuf0, rdata);
    check_data_unchanged("ProgBuf0 unchanged after busy write", rdata, 32'h1111_2222);

    clear_cmderr();

    // =========================================================================
    // TEST GROUP 6: Read ProgBuf0 while busy -> CmdErrBusy
    // =========================================================================
    $display("\n--- Test Group 6: Read ProgBuf0 while cmdbusy ---");

    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_read(dm::ProgBuf0, rdata);
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("Read ProgBuf0 while busy sets CmdErrBusy", cmderr_val, dm::CmdErrBusy);

    clear_cmderr();

    // =========================================================================
    // TEST GROUP 7: Write Command register while busy -> CmdErrBusy
    // (This was already in the original code, verify it still works)
    // =========================================================================
    $display("\n--- Test Group 7: Write Command while cmdbusy ---");

    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_write(dm::Command, 32'h0023_0000); // arbitrary command
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("Write Command while busy sets CmdErrBusy", cmderr_val, dm::CmdErrBusy);

    clear_cmderr();

    // =========================================================================
    // TEST GROUP 8: Write AbstractAuto while busy -> CmdErrBusy
    // =========================================================================
    $display("\n--- Test Group 8: Write AbstractAuto while cmdbusy ---");

    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_write(dm::AbstractAuto, 32'h0001_0001);
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("Write AbstractAuto while busy sets CmdErrBusy", cmderr_val, dm::CmdErrBusy);

    clear_cmderr();

    // =========================================================================
    // TEST GROUP 9: Write AbstractCS while busy -> CmdErrBusy
    // =========================================================================
    $display("\n--- Test Group 9: Write AbstractCS while cmdbusy ---");

    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_write(dm::AbstractCS, 32'h0000_0000);
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("Write AbstractCS while busy sets CmdErrBusy", cmderr_val, dm::CmdErrBusy);

    clear_cmderr();

    // =========================================================================
    // TEST GROUP 10: CmdErrBusy NOT set if cmderr already non-zero
    // (Patch 2: only set CmdErrBusy when cmderr_q == CmdErrNone)
    // =========================================================================
    $display("\n--- Test Group 10: CmdErrBusy not set when cmderr already non-zero ---");

    // Inject an existing error via cmderror_valid_i
    cmderror_valid_i = 1'b1;
    cmderror_i       = dm::CmdErrNotSupported; // value 2
    @(posedge clk_i);
    cmderror_valid_i = 1'b0;
    cmderror_i       = dm::CmdErrNone;
    repeat (2) @(posedge clk_i);

    // Verify error is set
    read_cmderr(cmderr_val);
    check("Pre-existing error is CmdErrNotSupported", cmderr_val, dm::CmdErrNotSupported);

    // Now attempt write Data0 while busy -- should NOT overwrite the existing error
    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_write(dm::Data0, 32'hBAAD_F00D);
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("cmderr stays CmdErrNotSupported (not overwritten by busy)", cmderr_val, dm::CmdErrNotSupported);

    clear_cmderr();

    // =========================================================================
    // TEST GROUP 11: CmdErrBusy NOT set on read Data0 if cmderr already non-zero
    // =========================================================================
    $display("\n--- Test Group 11: Read Data0 while busy, cmderr already non-zero ---");

    // Inject pre-existing error
    cmderror_valid_i = 1'b1;
    cmderror_i       = dm::CmdErrorException; // value 3
    @(posedge clk_i);
    cmderror_valid_i = 1'b0;
    cmderror_i       = dm::CmdErrNone;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("Pre-existing error is CmdErrorException", cmderr_val, dm::CmdErrorException);

    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_read(dm::Data0, rdata);
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("cmderr stays CmdErrorException on read Data0 while busy", cmderr_val, dm::CmdErrorException);

    clear_cmderr();

    // =========================================================================
    // TEST GROUP 12: CmdErrBusy NOT set on write ProgBuf if cmderr already non-zero
    // =========================================================================
    $display("\n--- Test Group 12: Write ProgBuf0 while busy, cmderr already non-zero ---");

    cmderror_valid_i = 1'b1;
    cmderror_i       = dm::CmdErrorHaltResume; // value 4
    @(posedge clk_i);
    cmderror_valid_i = 1'b0;
    cmderror_i       = dm::CmdErrNone;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("Pre-existing error is CmdErrorHaltResume", cmderr_val, dm::CmdErrorHaltResume);

    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_write(dm::ProgBuf0, 32'hFFFF_FFFF);
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("cmderr stays CmdErrorHaltResume on write ProgBuf0 while busy", cmderr_val, dm::CmdErrorHaltResume);

    clear_cmderr();

    // =========================================================================
    // TEST GROUP 13: CmdErrBusy NOT set on read ProgBuf if cmderr already non-zero
    // =========================================================================
    $display("\n--- Test Group 13: Read ProgBuf0 while busy, cmderr already non-zero ---");

    cmderror_valid_i = 1'b1;
    cmderror_i       = dm::CmdErrorBus; // value 5
    @(posedge clk_i);
    cmderror_valid_i = 1'b0;
    cmderror_i       = dm::CmdErrNone;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("Pre-existing error is CmdErrorBus", cmderr_val, dm::CmdErrorBus);

    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_read(dm::ProgBuf0, rdata);
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("cmderr stays CmdErrorBus on read ProgBuf0 while busy", cmderr_val, dm::CmdErrorBus);

    clear_cmderr();

    // =========================================================================
    // TEST GROUP 14: Normal (non-busy) data write should NOT set cmderr
    // =========================================================================
    $display("\n--- Test Group 14: Normal write Data0 while not busy ---");

    dmi_write(dm::Data0, 32'h5555_6666);
    repeat (3) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("Write Data0 when not busy: cmderr stays CmdErrNone", cmderr_val, dm::CmdErrNone);

    // Verify value was written
    dmi_read(dm::Data0, rdata);
    check_data_unchanged("Data0 correctly written when not busy", rdata, 32'h5555_6666);

    // =========================================================================
    // TEST GROUP 15: Normal (non-busy) progbuf write should NOT set cmderr
    // =========================================================================
    $display("\n--- Test Group 15: Normal write ProgBuf0 while not busy ---");

    dmi_write(dm::ProgBuf0, 32'h7777_8888);
    repeat (3) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("Write ProgBuf0 when not busy: cmderr stays CmdErrNone", cmderr_val, dm::CmdErrNone);

    dmi_read(dm::ProgBuf0, rdata);
    check_data_unchanged("ProgBuf0 correctly written when not busy", rdata, 32'h7777_8888);

    // =========================================================================
    // TEST GROUP 16: Write higher ProgBuf register while busy
    // =========================================================================
    $display("\n--- Test Group 16: Write ProgBuf1 (0x21) while cmdbusy ---");

    // Write known value while not busy
    dmi_write(7'h21, 32'hABCD_1234); // ProgBuf1 = 0x21
    repeat (2) @(posedge clk_i);

    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_write(7'h21, 32'h0000_0000);
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("Write ProgBuf1 while busy sets CmdErrBusy", cmderr_val, dm::CmdErrBusy);

    // ProgBuf1 should be unchanged
    dmi_read(7'h21, rdata);
    check_data_unchanged("ProgBuf1 unchanged after busy write", rdata, 32'hABCD_1234);

    clear_cmderr();

    // =========================================================================
    // TEST GROUP 17: Multiple busy accesses -- second should not overwrite
    // CmdErrBusy with CmdErrBusy (idempotent, just verifying)
    // =========================================================================
    $display("\n--- Test Group 17: Two writes to Data0 while busy ---");

    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_write(dm::Data0, 32'h1111_1111);
    repeat (2) @(posedge clk_i);

    // Second write while still busy -- cmderr already CmdErrBusy,
    // so the second access should NOT change it (stays CmdErrBusy)
    dmi_write(dm::Data0, 32'h2222_2222);
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("Two writes while busy: cmderr is still CmdErrBusy", cmderr_val, dm::CmdErrBusy);

    clear_cmderr();

    // =========================================================================
    // TEST GROUP 18: Write Command while busy, cmderr already non-zero
    // =========================================================================
    $display("\n--- Test Group 18: Write Command while busy, cmderr already non-zero ---");

    cmderror_valid_i = 1'b1;
    cmderror_i       = dm::CmdErrNotSupported;
    @(posedge clk_i);
    cmderror_valid_i = 1'b0;
    cmderror_i       = dm::CmdErrNone;
    repeat (2) @(posedge clk_i);

    cmdbusy_i = 1'b1;
    repeat (2) @(posedge clk_i);

    dmi_write(dm::Command, 32'h0023_0000);
    repeat (3) @(posedge clk_i);

    cmdbusy_i = 1'b0;
    repeat (2) @(posedge clk_i);

    read_cmderr(cmderr_val);
    check("cmderr stays CmdErrNotSupported on Command write while busy", cmderr_val, dm::CmdErrNotSupported);

    clear_cmderr();

    // =========================================================================
    // Summary
    // =========================================================================
    $display("\n====================================================");
    $display("  TEST SUMMARY: %0d passed, %0d failed out of %0d tests",
             pass_count, fail_count, test_num);
    $display("====================================================");

    if (fail_count == 0) begin
      $display("PASS: All tests passed.");
    end else begin
      $display("FAIL: %0d test(s) failed.", fail_count);
    end

    $display("Functional Coverage: %.1f%%", cg_inst.get_coverage());
    #20;
    $finish;
  end

  // ---------------------------------------------------------------------------
  // Patch-focused functional coverage
  // Patch: CmdErrBusy set on data/progbuf access while busy; only if cmderr==0
  // ---------------------------------------------------------------------------
  wire        cov_cmdbusy = cmdbusy_i;
  wire [2:0]  cov_cmderr  = dut.cmderr_q;
  wire        cov_dmi_valid = dmi_req_valid_i;
  wire [1:0]  cov_dmi_op  = dmi_req_i.op;

  covergroup cg_patch;
    cp_cmdbusy: coverpoint cov_cmdbusy {
      bins busy     = {1'b1};
      bins not_busy = {1'b0};
    }
    cp_cmderr: coverpoint cov_cmderr {
      bins none          = {3'd0};
      bins busy_err      = {3'd1};
      bins not_supported = {3'd2};
      bins exception     = {3'd3};
      bins halt_resume   = {3'd4};
      bins bus_err       = {3'd5};
    }
    cp_dmi_op: coverpoint cov_dmi_op iff (cov_dmi_valid) {
      bins read  = {2'h1};
      bins write = {2'h2};
    }
    cx_busy_cmderr: cross cp_cmdbusy, cp_cmderr;
    cx_busy_op: cross cp_cmdbusy, cp_dmi_op;
  endgroup

  cg_patch cg_inst = new();

  always @(posedge clk_i) begin
    if (rst_ni) cg_inst.sample();
  end

  // Timeout watchdog
  initial begin
    #100000;
    $display("FAIL: Simulation timeout");
    $finish;
  end

  initial begin
    $dumpfile("tb_dm_cmderr_busy_patch.vcd");
    $dumpvars(0);
  end

endmodule

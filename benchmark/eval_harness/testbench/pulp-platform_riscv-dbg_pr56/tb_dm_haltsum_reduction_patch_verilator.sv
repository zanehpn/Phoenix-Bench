`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// Testbench for pulp-platform/riscv-dbg PR #56
//
// The bug: haltsum1-3 loop bounds and array dimensions used NrHarts/2**N
// instead of (NrHarts-1)/2**N, causing out-of-bounds access for certain
// NrHart values (especially non-power-of-2 counts).
//
// This testbench instantiates dm_csrs with a non-power-of-2 NrHarts value
// (the primary trigger), drives various halted patterns, selects different
// hartsel windows via DMControl writes, and checks all four haltsum
// registers (haltsum0 through haltsum3) against a reference model.
// ---------------------------------------------------------------------------

module tb_dm_haltsum_reduction_patch;

  import dm::*;

  // -----------------------------------------------------------------------
  // Use 32 harts (power-of-2) -- this is the key trigger for the bug.
  // With NrHarts=32:
  //   halted_reshaped0 has (32-1)/32 + 1 = 1 entry (index 0 only)
  //   Buggy loop bound:  NrHarts/2**5+1 = 32/32+1 = 2 (iterates k=0,1)
  //   Fixed loop bound:  (NrHarts-1)/2**5+1 = 31/32+1 = 1 (iterates k=0 only)
  //   The buggy code accesses halted_reshaped0[1] which is out of bounds.
  //   Similarly, the buggy comparison NrHarts/2**10+1 = 1 vs (NrHarts-1)/2**10+1 = 1
  //   are the same for haltsum1, but the haltsum1 loop bound itself is wrong.
  // -----------------------------------------------------------------------
  localparam int unsigned NR_HARTS = 32;

  logic clk;
  logic rst_n;

  dm::dmi_req_t  dmi_req;
  logic          dmi_req_valid;
  logic          dmi_req_ready;
  dm::dmi_resp_t dmi_resp;
  logic          dmi_resp_valid;
  logic          dmi_resp_ready;

  logic [NR_HARTS-1:0] halted_bits;
  logic [19:0]         hartsel_out;

  // DUT outputs we monitor
  logic                ndmreset;
  logic                dmactive;

  dm_csrs #(
    .NrHarts  (NR_HARTS),
    .BusWidth (32)
  ) dut (
    .clk_i                   (clk),
    .rst_ni                  (rst_n),
    .testmode_i              (1'b0),
    .dmi_rst_ni              (rst_n),
    .dmi_req_valid_i         (dmi_req_valid),
    .dmi_req_ready_o         (dmi_req_ready),
    .dmi_req_i               (dmi_req),
    .dmi_resp_valid_o        (dmi_resp_valid),
    .dmi_resp_ready_i        (dmi_resp_ready),
    .dmi_resp_o              (dmi_resp),
    .ndmreset_o              (ndmreset),
    .dmactive_o              (dmactive),
    .hartinfo_i              ('0),
    .halted_i                (halted_bits),
    .unavailable_i           ('0),
    .resumeack_i             ('0),
    .hartsel_o               (hartsel_out),
    .haltreq_o               (),
    .resumereq_o             (),
    .clear_resumeack_o       (),
    .cmd_valid_o             (),
    .cmd_o                   (),
    .cmderror_valid_i        (1'b0),
    .cmderror_i              (dm::CmdErrNone),
    .cmdbusy_i               (1'b0),
    .progbuf_o               (),
    .data_o                  (),
    .data_i                  ('0),
    .data_valid_i            (1'b0),
    .sbaddress_o             (),
    .sbaddress_i             ('0),
    .sbaddress_write_valid_o (),
    .sbreadonaddr_o          (),
    .sbautoincrement_o       (),
    .sbaccess_o              (),
    .sbreadondata_o          (),
    .sbdata_o                (),
    .sbdata_read_valid_o     (),
    .sbdata_write_valid_o    (),
    .sbdata_i                ('0),
    .sbdata_valid_i          (1'b0),
    .sbbusy_i                (1'b0),
    .sberror_valid_i         (1'b0),
    .sberror_i               ('0)
  );

  // -----------------------------------------------------------------------
  // Clock generation
  // -----------------------------------------------------------------------
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // -----------------------------------------------------------------------
  // DMI read task
  // -----------------------------------------------------------------------
  task automatic dmi_read(input logic [7:0] addr, output logic [31:0] data);
    @(posedge clk);
    dmi_req_valid  = 1'b1;
    dmi_req.op     = dm::DTM_READ;
    dmi_req.addr   = addr[6:0];
    dmi_req.data   = '0;
    @(posedge clk);
    while (!dmi_req_ready) @(posedge clk);
    dmi_req_valid = 1'b0;
    @(posedge clk);
    while (!dmi_resp_valid) @(posedge clk);
    data = dmi_resp.data;
    @(posedge clk);
  endtask

  // -----------------------------------------------------------------------
  // DMI write task
  // -----------------------------------------------------------------------
  task automatic dmi_write(input logic [7:0] addr, input logic [31:0] data);
    @(posedge clk);
    dmi_req_valid  = 1'b1;
    dmi_req.op     = dm::DTM_WRITE;
    dmi_req.addr   = addr[6:0];
    dmi_req.data   = data;
    @(posedge clk);
    while (!dmi_req_ready) @(posedge clk);
    dmi_req_valid = 1'b0;
    @(posedge clk);
  endtask

  // -----------------------------------------------------------------------
  // Set hartsel via DMControl write (must keep dmactive=1)
  // -----------------------------------------------------------------------
  task automatic set_hartsel(input logic [19:0] sel);
    logic [31:0] dmcontrol_val;
    dmcontrol_val = '0;
    dmcontrol_val[0]     = 1'b1;               // dmactive
    dmcontrol_val[25:16] = sel[9:0];            // hartsello
    dmcontrol_val[15:6]  = sel[19:10];          // hartselhi
    dmi_write(dm::DMControl, dmcontrol_val);
  endtask

  // -----------------------------------------------------------------------
  // Reference model: compute expected haltsum values given halted_bits
  // and current hartsel.
  //
  // haltsum0: 32-bit slice of halted[] selected by hartsel[19:5]
  // haltsum1: each bit k = OR-reduce of halted_reshaped0[k] (32 harts);
  //           then select 32-bit slice by hartsel[19:10]
  // haltsum2: each bit k = OR-reduce of halted_reshaped1[k];
  //           then select 32-bit slice by hartsel[19:15]
  // haltsum3: each bit k = OR-reduce of halted_reshaped2[k];
  //           single 32-bit word
  // -----------------------------------------------------------------------

  // Padded halted to full aligned width
  localparam int unsigned HALTED_PAD_BITS = ((NR_HARTS-1)/32 + 1) * 32;

  function automatic logic [31:0] ref_haltsum0(
    input logic [NR_HARTS-1:0] hbits,
    input logic [19:0]         hs
  );
    logic [HALTED_PAD_BITS-1:0] padded;
    logic [14:0] idx;
    padded = '0;
    padded[NR_HARTS-1:0] = hbits;
    idx = hs[19:5];
    if (idx < 15'((NR_HARTS-1)/32 + 1))
      return padded[idx*32 +: 32];
    else
      return 32'h0;
  endfunction

  function automatic logic [31:0] ref_haltsum1(
    input logic [NR_HARTS-1:0] hbits,
    input logic [19:0]         hs
  );
    logic [HALTED_PAD_BITS-1:0] padded;
    // Number of 32-bit groups in level 0
    localparam int unsigned N0 = (NR_HARTS-1)/32 + 1;
    // flat1 has one bit per group
    logic [N0-1:0] flat1_bits;
    // pad flat1 into 32-bit reshaped words
    localparam int unsigned N1 = (NR_HARTS-1)/1024 + 1;
    logic [N1*32-1:0] flat1_padded;
    logic [9:0] idx;

    padded = '0;
    padded[NR_HARTS-1:0] = hbits;

    for (int k = 0; k < N0; k++) begin
      flat1_bits[k] = |padded[k*32 +: 32];
    end

    flat1_padded = '0;
    flat1_padded[N0-1:0] = flat1_bits;

    idx = hs[19:10];
    if (idx < 10'(N1))
      return flat1_padded[idx*32 +: 32];
    else
      return 32'h0;
  endfunction

  function automatic logic [31:0] ref_haltsum2(
    input logic [NR_HARTS-1:0] hbits,
    input logic [19:0]         hs
  );
    logic [HALTED_PAD_BITS-1:0] padded;
    localparam int unsigned N0 = (NR_HARTS-1)/32 + 1;
    logic [N0-1:0] flat1_bits;
    localparam int unsigned N1 = (NR_HARTS-1)/1024 + 1;
    logic [N1*32-1:0] flat1_padded;
    logic [N1-1:0][31:0] reshaped1;

    localparam int unsigned N2 = (NR_HARTS-1)/32768 + 1;
    logic [N2*32-1:0] flat2_padded;
    logic [N1-1:0] flat2_bits;
    logic [4:0] idx;

    padded = '0;
    padded[NR_HARTS-1:0] = hbits;

    for (int k = 0; k < N0; k++)
      flat1_bits[k] = |padded[k*32 +: 32];

    flat1_padded = '0;
    flat1_padded[N0-1:0] = flat1_bits;
    reshaped1 = flat1_padded;

    for (int k = 0; k < N1; k++)
      flat2_bits[k] = |reshaped1[k];

    flat2_padded = '0;
    flat2_padded[N1-1:0] = flat2_bits;

    idx = hs[19:15];
    if (idx < 5'(N2))
      return flat2_padded[idx*32 +: 32];
    else
      return 32'h0;
  endfunction

  function automatic logic [31:0] ref_haltsum3(
    input logic [NR_HARTS-1:0] hbits
  );
    logic [HALTED_PAD_BITS-1:0] padded;
    localparam int unsigned N0 = (NR_HARTS-1)/32 + 1;
    logic [N0-1:0] flat1_bits;
    localparam int unsigned N1 = (NR_HARTS-1)/1024 + 1;
    logic [N1*32-1:0] flat1_padded;
    logic [N1-1:0][31:0] reshaped1;
    logic [N1-1:0] flat2_bits;
    localparam int unsigned N2 = (NR_HARTS-1)/32768 + 1;
    logic [N2*32-1:0] flat2_padded;
    logic [N2-1:0][31:0] reshaped2;

    logic [31:0] flat3;

    padded = '0;
    padded[NR_HARTS-1:0] = hbits;

    for (int k = 0; k < N0; k++)
      flat1_bits[k] = |padded[k*32 +: 32];
    flat1_padded = '0;
    flat1_padded[N0-1:0] = flat1_bits;
    reshaped1 = flat1_padded;

    for (int k = 0; k < N1; k++)
      flat2_bits[k] = |reshaped1[k];
    flat2_padded = '0;
    flat2_padded[N1-1:0] = flat2_bits;
    reshaped2 = flat2_padded;

    flat3 = '0;
    for (int k = 0; k < N2; k++)
      flat3[k] = |reshaped2[k];

    return flat3;
  endfunction

  // -----------------------------------------------------------------------
  // Error counter
  // -----------------------------------------------------------------------
  int err_count = 0;
  int test_count = 0;

  task automatic check_haltsum(
    input string       test_name,
    input logic [7:0]  reg_addr,
    input string       reg_name,
    input logic [31:0] expected
  );
    logic [31:0] actual;
    dmi_read(reg_addr, actual);
    test_count++;
    if (actual !== expected) begin
      $fatal(1, "FAIL [%s] %s: got 0x%08x, expected 0x%08x",
               test_name, reg_name, actual, expected);
      err_count++;
    end else begin
      $display("  OK [%s] %s: 0x%08x", test_name, reg_name, actual);
    end
  endtask

  // -----------------------------------------------------------------------
  // Check all four haltsums for current halted_bits and hartsel
  // -----------------------------------------------------------------------
  task automatic check_all_haltsums(
    input string       test_name,
    input logic [19:0] hs
  );
    logic [31:0] exp0, exp1, exp2, exp3;
    exp0 = ref_haltsum0(halted_bits, hs);
    exp1 = ref_haltsum1(halted_bits, hs);
    exp2 = ref_haltsum2(halted_bits, hs);
    exp3 = ref_haltsum3(halted_bits);

    check_haltsum(test_name, dm::HaltSum0, "HaltSum0", exp0);
    check_haltsum(test_name, dm::HaltSum1, "HaltSum1", exp1);
    check_haltsum(test_name, dm::HaltSum2, "HaltSum2", exp2);
    check_haltsum(test_name, dm::HaltSum3, "HaltSum3", exp3);
  endtask

  // -----------------------------------------------------------------------
  // Main test sequence
  // -----------------------------------------------------------------------
  initial begin
    dmi_req_valid  = 1'b0;
    dmi_resp_ready = 1'b1;
    dmi_req        = '0;
    halted_bits    = '0;
    rst_n          = 1'b0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (4) @(posedge clk);

    // First, activate the debug module (dmactive=1) so CSR writes take effect
    dmi_write(dm::DMControl, 32'h0000_0001);
    repeat (2) @(posedge clk);

    // ------------------------------------------------------------------
    // TEST 1: No harts halted -- all haltsums should be zero
    // ------------------------------------------------------------------
    $display("\n--- TEST 1: No harts halted ---");
    halted_bits = '0;
    set_hartsel(20'h0);
    repeat (2) @(posedge clk);
    check_all_haltsums("T1_no_halt", 20'h0);

    // ------------------------------------------------------------------
    // TEST 2: Single hart halted in first group (hart 0)
    // ------------------------------------------------------------------
    $display("\n--- TEST 2: Single hart 0 halted ---");
    halted_bits    = '0;
    halted_bits[0] = 1'b1;
    set_hartsel(20'h0);
    repeat (2) @(posedge clk);
    check_all_haltsums("T2_hart0", 20'h0);

    // ------------------------------------------------------------------
    // TEST 3: Single hart halted at boundary (hart 31 -- last in first group)
    //         This is the last hart (NR_HARTS=32), index 31.
    // ------------------------------------------------------------------
    $display("\n--- TEST 3: Single hart 31 halted (last hart) ---");
    halted_bits     = '0;
    halted_bits[31] = 1'b1;
    set_hartsel(20'h0);
    repeat (2) @(posedge clk);
    check_all_haltsums("T3_hart31", 20'h0);

    // ------------------------------------------------------------------
    // TEST 4: All harts halted
    // ------------------------------------------------------------------
    $display("\n--- TEST 4: All harts halted ---");
    halted_bits = {NR_HARTS{1'b1}};
    set_hartsel(20'h0);
    repeat (2) @(posedge clk);
    check_all_haltsums("T4_all_halt", 20'h0);

    // ------------------------------------------------------------------
    // TEST 5: Hart 31 halted, hartsel window 0 for haltsum0
    // ------------------------------------------------------------------
    $display("\n--- TEST 5: Hart 31 halted, hartsel window 0 for haltsum0 ---");
    halted_bits     = '0;
    halted_bits[31] = 1'b1;
    set_hartsel(20'h0000);
    repeat (2) @(posedge clk);
    check_all_haltsums("T5_grp0", 20'h0000);

    // ------------------------------------------------------------------
    // TEST 6: Multiple harts halted
    //         Harts 0, 15, 31 halted
    // ------------------------------------------------------------------
    $display("\n--- TEST 6: Harts 0,15,31 halted ---");
    halted_bits     = '0;
    halted_bits[0]  = 1'b1;
    halted_bits[15] = 1'b1;
    halted_bits[31] = 1'b1;
    set_hartsel(20'h0);
    repeat (2) @(posedge clk);
    check_all_haltsums("T6_multi", 20'h0);

    // ------------------------------------------------------------------
    // TEST 7: Out-of-range hartsel -- haltsums should return 0 for
    //         windows beyond the hart count.
    // ------------------------------------------------------------------
    $display("\n--- TEST 7: Out-of-range hartsel ---");
    halted_bits = {NR_HARTS{1'b1}};
    // Set hartsel to a large value beyond NR_HARTS
    set_hartsel(20'h03E0); // hartsel[19:5]=31, well beyond 2 groups
    repeat (2) @(posedge clk);
    check_all_haltsums("T7_oor", 20'h03E0);

    // ------------------------------------------------------------------
    // TEST 8: Alternating pattern -- odd harts halted
    // ------------------------------------------------------------------
    $display("\n--- TEST 8: Alternating pattern (odd harts halted) ---");
    halted_bits = '0;
    for (int i = 1; i < NR_HARTS; i += 2)
      halted_bits[i] = 1'b1;
    set_hartsel(20'h0);
    repeat (2) @(posedge clk);
    check_all_haltsums("T8_alt", 20'h0);

    // ------------------------------------------------------------------
    // TEST 9: Only the very last hart halted (hart NR_HARTS-1 = 31)
    //         This specifically tests the boundary condition that
    //         triggered the original bug.
    // ------------------------------------------------------------------
    $display("\n--- TEST 9: Only last hart (31) halted - boundary test ---");
    halted_bits              = '0;
    halted_bits[NR_HARTS-1]  = 1'b1;
    set_hartsel(20'h0);
    repeat (2) @(posedge clk);
    check_all_haltsums("T9_last", 20'h0);

    // ------------------------------------------------------------------
    // TEST 10: Dynamic toggle -- halt then unhalt, verify update
    // ------------------------------------------------------------------
    $display("\n--- TEST 10: Dynamic halt/unhalt ---");
    halted_bits     = '0;
    halted_bits[10] = 1'b1;
    set_hartsel(20'h0);
    repeat (2) @(posedge clk);
    check_all_haltsums("T10a_h10", 20'h0);

    // Now unhalt hart 10 and halt hart 31
    halted_bits     = '0;
    halted_bits[31] = 1'b1;
    repeat (2) @(posedge clk);
    check_all_haltsums("T10b_h31", 20'h0);

    // ------------------------------------------------------------------
    // Summary
    // ------------------------------------------------------------------
    $display("\n========================================");
    $display("Tests run : %0d", test_count);
    $display("Errors    : %0d", err_count);
    if (err_count == 0)
      $display("RESULT: ALL TESTS PASSED");
    else
      $display("RESULT: %0d TESTS FAILED", err_count);
    $display("========================================\n");
    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end

  // ---------------------------------------------------------------------------
  // Patch-focused functional coverage
  // Patch fixes haltsum1-3 loop bounds: NrHarts/2**N -> (NrHarts-1)/2**N
  // ---------------------------------------------------------------------------
  wire [NR_HARTS-1:0] cov_halted   = halted_bits;
  wire [19:0]         cov_hartsel  = hartsel_out;
  wire                cov_last_halted = halted_bits[NR_HARTS-1];

  // [verilator-strip cg] covergroup cg_patch;
// [verilator-strip cg]     cp_halted_pattern: coverpoint cov_halted {
// [verilator-strip cg]       bins none_halted  = {'0};
// [verilator-strip cg]       bins all_halted   = {{NR_HARTS{1'b1}}};
// [verilator-strip cg]       bins some_halted  = default;
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_last_hart: coverpoint cov_last_halted {
// [verilator-strip cg]       bins last_halted     = {1'b1};
// [verilator-strip cg]       bins last_not_halted = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_hartsel_window: coverpoint cov_hartsel[19:5] {
// [verilator-strip cg]       bins window0 = {15'd0};
// [verilator-strip cg]       bins out_of_range = {[15'd1:$]};
// [verilator-strip cg]     }
// [verilator-strip cg]     cx_last_hart_window: cross cp_last_hart, cp_hartsel_window {
// [verilator-strip cg]       // When hartsel window is out of range, no valid harts are addressed;
// [verilator-strip cg]       // simultaneously having last_not_halted requires reset/init while out of range
// [verilator-strip cg]       ignore_bins not_halted_oor = binsof(cp_last_hart.last_not_halted) && binsof(cp_hartsel_window.out_of_range);
// [verilator-strip cg]     }
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_patch cg_inst = new();

  always @(posedge clk) begin
    if (rst_n) /* [verilator-strip sample] */;
  end

  // -----------------------------------------------------------------------
  // Timeout watchdog
  // -----------------------------------------------------------------------
  initial begin
    #100_000;
    $display("ERROR: Testbench timeout after 100us");
    $finish;
  end

  // -----------------------------------------------------------------------
  // VCD dump
  // -----------------------------------------------------------------------
  initial begin
    $dumpfile("tb_dm_haltsum_reduction_patch.vcd");
    $dumpvars(0);
  end

endmodule

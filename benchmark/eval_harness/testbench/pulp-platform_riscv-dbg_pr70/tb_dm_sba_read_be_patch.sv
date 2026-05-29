`timescale 1ns/1ps

module tb_dm_sba_read_be_patch;

  // ---------------------------------------------------------------
  // Parameters
  // ---------------------------------------------------------------
  localparam int unsigned BUS_WIDTH = 32;
  localparam int unsigned BE_WIDTH  = BUS_WIDTH / 8;

  // ---------------------------------------------------------------
  // Signals
  // ---------------------------------------------------------------
  logic clk;
  logic rst_n;

  // System bus interface
  logic                   master_req;
  logic [BUS_WIDTH-1:0]   master_addr;
  logic                   master_we;
  logic [BUS_WIDTH-1:0]   master_wdata;
  logic [BE_WIDTH-1:0]    master_be;
  logic                   master_gnt;
  logic                   master_r_valid;
  logic [BUS_WIDTH-1:0]   master_r_rdata;

  // SBA programming interface
  logic [BUS_WIDTH-1:0]   sbaddress;
  logic                   sbaddress_write_valid;
  logic                   sbreadonaddr;
  logic [2:0]             sbaccess;
  logic                   sbautoincrement;
  logic                   sbreadondata;
  logic [BUS_WIDTH-1:0]   sbdata;
  logic                   sbdata_read_valid;
  logic                   sbdata_write_valid;
  logic                   dmactive;

  logic [BUS_WIDTH-1:0]   sbaddress_o;
  logic [BUS_WIDTH-1:0]   sbdata_o;
  logic                   sbdata_valid_o;
  logic                   sbbusy;
  logic                   sberror_valid;
  logic [2:0]             sberror;

  // ---------------------------------------------------------------
  // Test counters
  // ---------------------------------------------------------------
  int pass_count = 0;
  int fail_count = 0;

  // ---------------------------------------------------------------
  // DUT: ReadByteEnable = 1 (default, new behavior)
  // ---------------------------------------------------------------
  dm_sba #(
    .BusWidth(BUS_WIDTH),
    .ReadByteEnable(1)
  ) dut (
    .clk_i              (clk),
    .rst_ni             (rst_n),
    .dmactive_i         (dmactive),
    .master_req_o       (master_req),
    .master_add_o       (master_addr),
    .master_we_o        (master_we),
    .master_wdata_o     (master_wdata),
    .master_be_o        (master_be),
    .master_gnt_i       (master_gnt),
    .master_r_valid_i   (master_r_valid),
    .master_r_rdata_i   (master_r_rdata),
    .sbaddress_i        (sbaddress),
    .sbaddress_write_valid_i(sbaddress_write_valid),
    .sbreadonaddr_i     (sbreadonaddr),
    .sbaddress_o        (sbaddress_o),
    .sbautoincrement_i  (sbautoincrement),
    .sbaccess_i         (sbaccess),
    .sbreadondata_i     (sbreadondata),
    .sbdata_i           (sbdata),
    .sbdata_read_valid_i(sbdata_read_valid),
    .sbdata_write_valid_i(sbdata_write_valid),
    .sbdata_o           (sbdata_o),
    .sbdata_valid_o     (sbdata_valid_o),
    .sbbusy_o           (sbbusy),
    .sberror_valid_o    (sberror_valid),
    .sberror_o          (sberror)
  );

  // ---------------------------------------------------------------
  // Signals for second DUT instance (ReadByteEnable = 0)
  // ---------------------------------------------------------------
  logic                   master_req_nb;
  logic [BUS_WIDTH-1:0]   master_addr_nb;
  logic                   master_we_nb;
  logic [BUS_WIDTH-1:0]   master_wdata_nb;
  logic [BE_WIDTH-1:0]    master_be_nb;

  logic [BUS_WIDTH-1:0]   sbaddress_o_nb;
  logic [BUS_WIDTH-1:0]   sbdata_o_nb;
  logic                   sbdata_valid_o_nb;
  logic                   sbbusy_nb;
  logic                   sberror_valid_nb;
  logic [2:0]             sberror_nb;

  // Second DUT with ReadByteEnable disabled (old behavior)
  dm_sba #(
    .BusWidth(BUS_WIDTH),
    .ReadByteEnable(0)
  ) dut_no_rbe (
    .clk_i              (clk),
    .rst_ni             (rst_n),
    .dmactive_i         (dmactive),
    .master_req_o       (master_req_nb),
    .master_add_o       (master_addr_nb),
    .master_we_o        (master_we_nb),
    .master_wdata_o     (master_wdata_nb),
    .master_be_o        (master_be_nb),
    .master_gnt_i       (master_gnt),
    .master_r_valid_i   (master_r_valid),
    .master_r_rdata_i   (master_r_rdata),
    .sbaddress_i        (sbaddress),
    .sbaddress_write_valid_i(sbaddress_write_valid),
    .sbreadonaddr_i     (sbreadonaddr),
    .sbaddress_o        (sbaddress_o_nb),
    .sbautoincrement_i  (sbautoincrement),
    .sbaccess_i         (sbaccess),
    .sbreadondata_i     (sbreadondata),
    .sbdata_i           (sbdata),
    .sbdata_read_valid_i(sbdata_read_valid),
    .sbdata_write_valid_i(sbdata_write_valid),
    .sbdata_o           (sbdata_o_nb),
    .sbdata_valid_o     (sbdata_valid_o_nb),
    .sbbusy_o           (sbbusy_nb),
    .sberror_valid_o    (sberror_valid_nb),
    .sberror_o          (sberror_nb)
  );

  // ---------------------------------------------------------------
  // Clock generation
  // ---------------------------------------------------------------
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  // ---------------------------------------------------------------
  // Reset
  // ---------------------------------------------------------------
  task automatic do_reset();
    rst_n = 1'b0;
    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    repeat (2) @(posedge clk);
  endtask

  // ---------------------------------------------------------------
  // Initialize all inputs to safe defaults
  // ---------------------------------------------------------------
  task automatic init_signals();
    master_gnt            = 1'b0;
    master_r_valid        = 1'b0;
    master_r_rdata        = '0;
    sbaddress             = '0;
    sbaddress_write_valid = 1'b0;
    sbreadonaddr          = 1'b0;
    sbaccess              = 3'b000;
    sbautoincrement       = 1'b0;
    sbreadondata          = 1'b0;
    sbdata                = '0;
    sbdata_read_valid     = 1'b0;
    sbdata_write_valid    = 1'b0;
    dmactive              = 1'b1;
  endtask

  // ---------------------------------------------------------------
  // Check helper
  // ---------------------------------------------------------------
  task automatic check(input string test_name, input bit condition);
    if (condition) begin
      pass_count++;
      $display("  [PASS] %s", test_name);
    end else begin
      fail_count++;
      $display("  [FAIL] %s", test_name);
    end
  endtask

  // ---------------------------------------------------------------
  // Task: Perform a read via sbreadonaddr and check BE
  // Uses the primary DUT (ReadByteEnable=1)
  // ---------------------------------------------------------------
  task automatic do_read_via_addr(
    input logic [BUS_WIDTH-1:0] addr,
    input logic [2:0]           access,
    input logic [BE_WIDTH-1:0]  expected_be,
    input logic [BUS_WIDTH-1:0] rdata,
    input string                label
  );
    sbaddress             = addr;
    sbaccess              = access;
    sbaddress_write_valid = 1'b1;
    sbreadonaddr          = 1'b1;
    @(posedge clk);
    sbaddress_write_valid = 1'b0;
    sbreadonaddr          = 1'b0;

    // Wait for master_req to assert (Read state)
    wait (master_req === 1'b1);

    // Check BE on the same cycle master_req is high
    check($sformatf("%s: BE=%0b expected=%0b", label, master_be, expected_be),
          master_be === expected_be);

    // Check we is low for reads
    check($sformatf("%s: master_we=0 for read", label),
          master_we === 1'b0);

    // Grant the request
    @(posedge clk);
    master_gnt = 1'b1;
    @(posedge clk);
    master_gnt = 1'b0;

    // Return read data
    master_r_valid = 1'b1;
    master_r_rdata = rdata;
    @(posedge clk);
    master_r_valid = 1'b0;
    master_r_rdata = '0;

    // Wait for SBA to go idle
    wait (sbbusy === 1'b0);
    @(posedge clk);
  endtask

  // ---------------------------------------------------------------
  // Task: Perform a read via sbreadondata and check BE
  // ---------------------------------------------------------------
  task automatic do_read_via_data(
    input logic [BUS_WIDTH-1:0] addr,
    input logic [2:0]           access,
    input logic [BE_WIDTH-1:0]  expected_be,
    input logic [BUS_WIDTH-1:0] rdata,
    input string                label
  );
    sbaddress         = addr;
    sbaccess          = access;
    sbreadondata      = 1'b1;
    sbdata_read_valid = 1'b1;
    @(posedge clk);
    sbdata_read_valid = 1'b0;
    sbreadondata      = 1'b0;

    wait (master_req === 1'b1);

    check($sformatf("%s: BE=%0b expected=%0b", label, master_be, expected_be),
          master_be === expected_be);

    @(posedge clk);
    master_gnt = 1'b1;
    @(posedge clk);
    master_gnt = 1'b0;

    master_r_valid = 1'b1;
    master_r_rdata = rdata;
    @(posedge clk);
    master_r_valid = 1'b0;
    master_r_rdata = '0;

    wait (sbbusy === 1'b0);
    @(posedge clk);
  endtask

  // ---------------------------------------------------------------
  // Task: Perform a write and check BE
  // ---------------------------------------------------------------
  task automatic do_write(
    input logic [BUS_WIDTH-1:0] addr,
    input logic [2:0]           access,
    input logic [BUS_WIDTH-1:0] wdata,
    input logic [BE_WIDTH-1:0]  expected_be,
    input string                label
  );
    sbaddress          = addr;
    sbaccess           = access;
    sbdata             = wdata;
    sbdata_write_valid = 1'b1;
    @(posedge clk);
    sbdata_write_valid = 1'b0;

    wait (master_req === 1'b1);

    check($sformatf("%s: BE=%0b expected=%0b", label, master_be, expected_be),
          master_be === expected_be);
    check($sformatf("%s: master_we=1 for write", label),
          master_we === 1'b1);
    check($sformatf("%s: wdata=0x%0h", label, master_wdata),
          master_wdata === wdata);

    @(posedge clk);
    master_gnt = 1'b1;
    @(posedge clk);
    master_gnt = 1'b0;

    master_r_valid = 1'b1;
    @(posedge clk);
    master_r_valid = 1'b0;

    wait (sbbusy === 1'b0);
    @(posedge clk);
  endtask

  // ---------------------------------------------------------------
  // Main test sequence
  // ---------------------------------------------------------------
  initial begin
    init_signals();
    do_reset();

    // ===========================================================
    // TEST GROUP 1: Read byte-enables for all sbaccess sizes
    //               (core bug fix verification)
    // ===========================================================
    $display("\n=== TEST GROUP 1: Read BE for byte access (sbaccess=0) ===");
    do_read_via_addr(32'h0000_0000, 3'b000, 4'b0001, 32'hAABBCCDD,
                     "Read byte at addr[1:0]=00");
    do_read_via_addr(32'h0000_0001, 3'b000, 4'b0010, 32'hAABBCCDD,
                     "Read byte at addr[1:0]=01");
    do_read_via_addr(32'h0000_0002, 3'b000, 4'b0100, 32'hAABBCCDD,
                     "Read byte at addr[1:0]=10");
    do_read_via_addr(32'h0000_0003, 3'b000, 4'b1000, 32'hAABBCCDD,
                     "Read byte at addr[1:0]=11");

    $display("\n=== TEST GROUP 2: Read BE for halfword access (sbaccess=1) ===");
    do_read_via_addr(32'h0000_0000, 3'b001, 4'b0011, 32'h11223344,
                     "Read half at addr[1:0]=00");
    do_read_via_addr(32'h0000_0002, 3'b001, 4'b1100, 32'h11223344,
                     "Read half at addr[1:0]=10");
    // Odd address with halfword: bit 0 gets masked to 0 by the hardware
    do_read_via_addr(32'h0000_0001, 3'b001, 4'b0011, 32'h11223344,
                     "Read half at addr[1:0]=01 (aligned to 00)");
    do_read_via_addr(32'h0000_0003, 3'b001, 4'b1100, 32'h11223344,
                     "Read half at addr[1:0]=11 (aligned to 10)");

    $display("\n=== TEST GROUP 3: Read BE for word access (sbaccess=2, BusWidth=32) ===");
    do_read_via_addr(32'h0000_0000, 3'b010, 4'b1111, 32'hDEADBEEF,
                     "Read word at addr=0x0");
    do_read_via_addr(32'h0000_0004, 3'b010, 4'b1111, 32'hCAFEBABE,
                     "Read word at addr=0x4");
    do_read_via_addr(32'h1000_0100, 3'b010, 4'b1111, 32'h12345678,
                     "Read word at high addr");

    // ===========================================================
    // TEST GROUP 4: Write byte-enables (regression: still correct
    //               after refactoring be_mask out of Write block)
    // ===========================================================
    $display("\n=== TEST GROUP 4: Write BE for byte access (sbaccess=0) ===");
    do_write(32'h0000_0000, 3'b000, 32'h000000AA, 4'b0001,
             "Write byte at addr[1:0]=00");
    do_write(32'h0000_0001, 3'b000, 32'h0000BB00, 4'b0010,
             "Write byte at addr[1:0]=01");
    do_write(32'h0000_0002, 3'b000, 32'h00CC0000, 4'b0100,
             "Write byte at addr[1:0]=10");
    do_write(32'h0000_0003, 3'b000, 32'hDD000000, 4'b1000,
             "Write byte at addr[1:0]=11");

    $display("\n=== TEST GROUP 5: Write BE for halfword access (sbaccess=1) ===");
    do_write(32'h0000_0000, 3'b001, 32'h0000AABB, 4'b0011,
             "Write half at addr[1:0]=00");
    do_write(32'h0000_0002, 3'b001, 32'hCCDD0000, 4'b1100,
             "Write half at addr[1:0]=10");

    $display("\n=== TEST GROUP 6: Write BE for word access (sbaccess=2) ===");
    do_write(32'h0000_0000, 3'b010, 32'hDEADBEEF, 4'b1111,
             "Write word at addr=0x0");

    // ===========================================================
    // TEST GROUP 7: Read and Write BE match for same parameters
    // ===========================================================
    $display("\n=== TEST GROUP 7: Read/Write BE symmetry ===");
    begin
      logic [2:0] acc;
      logic [BUS_WIDTH-1:0] test_addr;
      logic [BE_WIDTH-1:0] expected;
      // For each access size, do a write then a read and ensure BEs match
      for (int a = 0; a < 3; a++) begin
        acc = a[2:0];
        test_addr = 32'h0000_0000;
        // Compute expected
        case (acc)
          3'b000: expected = 4'b0001;
          3'b001: expected = 4'b0011;
          3'b010: expected = 4'b1111;
          default: expected = 4'b1111;
        endcase
        do_write(test_addr, acc, 32'hA5A5A5A5, expected,
                 $sformatf("Symmetry write sbaccess=%0d", a));
        do_read_via_addr(test_addr, acc, expected, 32'h5A5A5A5A,
                 $sformatf("Symmetry read  sbaccess=%0d", a));
      end
    end

    // ===========================================================
    // TEST GROUP 8: sbreadondata path triggers read correctly
    // ===========================================================
    $display("\n=== TEST GROUP 8: Read via sbreadondata ===");
    do_read_via_data(32'h0000_0000, 3'b000, 4'b0001, 32'hFEEDFACE,
                     "sbreadondata byte at addr=0x0");
    do_read_via_data(32'h0000_0002, 3'b001, 4'b1100, 32'h12345678,
                     "sbreadondata half at addr=0x2");
    do_read_via_data(32'h0000_0000, 3'b010, 4'b1111, 32'hCAFEBABE,
                     "sbreadondata word at addr=0x0");

    // ===========================================================
    // TEST GROUP 9: sbdata_o reflects read data correctly
    //   sbdata_o is a combinational pass-through of master_r_rdata_i,
    //   so we check it while master_r_valid is still asserted.
    // ===========================================================
    $display("\n=== TEST GROUP 9: Read data output ===");
    begin
      logic [BUS_WIDTH-1:0] rdata_test;
      rdata_test = 32'h87654321;

      sbaddress             = 32'h0000_0000;
      sbaccess              = 3'b010;
      sbaddress_write_valid = 1'b1;
      sbreadonaddr          = 1'b1;
      @(posedge clk);
      sbaddress_write_valid = 1'b0;
      sbreadonaddr          = 1'b0;

      wait (master_req === 1'b1);
      @(posedge clk);
      master_gnt = 1'b1;
      @(posedge clk);
      master_gnt = 1'b0;

      master_r_valid = 1'b1;
      master_r_rdata = rdata_test;
      // Check sbdata_o on same cycle master_r_valid is driven
      // (combinational path: sbdata_o = master_r_rdata_i)
      @(posedge clk);
      // Now check at beginning of next cycle while r_valid is still registered
      check($sformatf("sbdata_o=0x%0h during valid", sbdata_o),
            sbdata_o === rdata_test);
      master_r_valid = 1'b0;
      master_r_rdata = '0;

      wait (sbbusy === 1'b0);
      @(posedge clk);
    end

    // ===========================================================
    // TEST GROUP 10: Auto-increment address
    //   sbaddress_o is combinational: it shows the incremented
    //   value only during WaitRead/WaitWrite when r_valid is high.
    //   We capture it at that moment.
    // ===========================================================
    $display("\n=== TEST GROUP 10: Auto-increment ===");
    begin
      logic [BUS_WIDTH-1:0] captured_addr;

      sbautoincrement = 1'b1;

      // --- Byte access auto-increment: +1 ---
      sbaddress             = 32'h0000_1000;
      sbaccess              = 3'b000;
      sbaddress_write_valid = 1'b1;
      sbreadonaddr          = 1'b1;
      @(posedge clk);
      sbaddress_write_valid = 1'b0;
      sbreadonaddr          = 1'b0;
      wait (master_req === 1'b1);
      @(posedge clk);
      master_gnt = 1'b1;
      @(posedge clk);
      master_gnt = 1'b0;
      master_r_valid = 1'b1;
      master_r_rdata = 32'h11;
      @(posedge clk);
      // Capture sbaddress_o on the cycle r_valid was seen
      captured_addr = sbaddress_o;
      master_r_valid = 1'b0;
      check($sformatf("Auto-inc byte: sbaddress_o=0x%0h, expected 0x1001", captured_addr),
            captured_addr === 32'h0000_1001);
      wait (sbbusy === 1'b0);
      @(posedge clk);

      // --- Halfword access auto-increment: +2 ---
      sbaddress             = 32'h0000_2000;
      sbaccess              = 3'b001;
      sbaddress_write_valid = 1'b1;
      sbreadonaddr          = 1'b1;
      @(posedge clk);
      sbaddress_write_valid = 1'b0;
      sbreadonaddr          = 1'b0;
      wait (master_req === 1'b1);
      @(posedge clk);
      master_gnt = 1'b1;
      @(posedge clk);
      master_gnt = 1'b0;
      master_r_valid = 1'b1;
      master_r_rdata = 32'h2222;
      @(posedge clk);
      captured_addr = sbaddress_o;
      master_r_valid = 1'b0;
      check($sformatf("Auto-inc half: sbaddress_o=0x%0h, expected 0x2002", captured_addr),
            captured_addr === 32'h0000_2002);
      wait (sbbusy === 1'b0);
      @(posedge clk);

      // --- Word access auto-increment: +4 ---
      sbaddress             = 32'h0000_3000;
      sbaccess              = 3'b010;
      sbaddress_write_valid = 1'b1;
      sbreadonaddr          = 1'b1;
      @(posedge clk);
      sbaddress_write_valid = 1'b0;
      sbreadonaddr          = 1'b0;
      wait (master_req === 1'b1);
      @(posedge clk);
      master_gnt = 1'b1;
      @(posedge clk);
      master_gnt = 1'b0;
      master_r_valid = 1'b1;
      master_r_rdata = 32'h33333333;
      @(posedge clk);
      captured_addr = sbaddress_o;
      master_r_valid = 1'b0;
      check($sformatf("Auto-inc word: sbaddress_o=0x%0h, expected 0x3004", captured_addr),
            captured_addr === 32'h0000_3004);
      wait (sbbusy === 1'b0);
      @(posedge clk);

      // --- Auto-increment on write: +4 ---
      sbaddress          = 32'h0000_4000;
      sbaccess           = 3'b010;
      sbdata             = 32'hAAAAAAAA;
      sbdata_write_valid = 1'b1;
      @(posedge clk);
      sbdata_write_valid = 1'b0;
      wait (master_req === 1'b1);
      @(posedge clk);
      master_gnt = 1'b1;
      @(posedge clk);
      master_gnt = 1'b0;
      master_r_valid = 1'b1;
      @(posedge clk);
      captured_addr = sbaddress_o;
      master_r_valid = 1'b0;
      check($sformatf("Auto-inc write word: sbaddress_o=0x%0h, expected 0x4004", captured_addr),
            captured_addr === 32'h0000_4004);
      wait (sbbusy === 1'b0);
      @(posedge clk);

      sbautoincrement = 1'b0;
    end

    // ===========================================================
    // TEST GROUP 11: No auto-increment when disabled
    // ===========================================================
    $display("\n=== TEST GROUP 11: No auto-increment when disabled ===");
    begin
      sbautoincrement = 1'b0;
      do_read_via_addr(32'h0000_5000, 3'b010, 4'b1111, 32'h55555555,
                       "No auto-inc read");
      check($sformatf("No auto-inc: sbaddress_o=0x%0h, expected 0x5000",
                       sbaddress_o),
            sbaddress_o === 32'h0000_5000);
    end

    // ===========================================================
    // TEST GROUP 12: Error on sbaccess > 3
    //   Error fires combinationally when (sbaccess_i > 3 && state_q != Idle).
    //   So after Idle->Read transition (1 clock), when state_q=Read,
    //   the error outputs appear on the same cycle.
    // ===========================================================
    $display("\n=== TEST GROUP 12: Error on oversized access ===");
    begin
      // Trigger a read with sbaccess=4 (> 3), should produce error
      sbaddress             = 32'h0000_0000;
      sbaccess              = 3'b100;  // 16-byte, unsupported
      sbaddress_write_valid = 1'b1;
      sbreadonaddr          = 1'b1;
      @(posedge clk);
      sbaddress_write_valid = 1'b0;
      sbreadonaddr          = 1'b0;

      // After this clock edge, state_q transitions from Idle to Read.
      // On the next combinational eval, sbaccess_i > 3 && state_q == Read
      // produces sberror_valid = 1, sberror = 3, and state_d = Idle.
      @(posedge clk);
      // Now state_q = Read, error outputs are combinationally active
      check($sformatf("Error valid asserted for sbaccess=4"),
            sberror_valid === 1'b1);
      check($sformatf("Error code=3 for sbaccess=4, got=%0d", sberror),
            sberror === 3'd3);
      check("req suppressed during error", master_req === 1'b0);

      // After one more clock, state_q = Idle (state_d was set to Idle)
      @(posedge clk);
      check("Back to idle after error", sbbusy === 1'b0);
      sbaccess = 3'b000;  // restore
      @(posedge clk);
    end

    // ===========================================================
    // TEST GROUP 13: sbbusy signal behavior
    // ===========================================================
    $display("\n=== TEST GROUP 13: sbbusy signal ===");
    begin
      check("sbbusy=0 in Idle", sbbusy === 1'b0);

      // Start a read, check sbbusy goes high
      sbaddress             = 32'h0000_0000;
      sbaccess              = 3'b010;
      sbaddress_write_valid = 1'b1;
      sbreadonaddr          = 1'b1;
      @(posedge clk);
      sbaddress_write_valid = 1'b0;
      sbreadonaddr          = 1'b0;
      @(posedge clk);
      check("sbbusy=1 during read", sbbusy === 1'b1);

      // Complete the transaction
      master_gnt = 1'b1;
      @(posedge clk);
      master_gnt = 1'b0;
      master_r_valid = 1'b1;
      master_r_rdata = 32'h0;
      @(posedge clk);
      master_r_valid = 1'b0;
      wait (sbbusy === 1'b0);
      check("sbbusy=0 after read completes", sbbusy === 1'b0);
      @(posedge clk);
    end

    // ===========================================================
    // TEST GROUP 14: ReadByteEnable=0 instance (old behavior)
    //   Verify that the second DUT drives BE=0 during reads
    // ===========================================================
    $display("\n=== TEST GROUP 14: ReadByteEnable=0 old behavior ===");
    begin
      // Trigger a read on both DUTs simultaneously (same inputs)
      sbaddress             = 32'h0000_0000;
      sbaccess              = 3'b000;  // byte access
      sbaddress_write_valid = 1'b1;
      sbreadonaddr          = 1'b1;
      @(posedge clk);
      sbaddress_write_valid = 1'b0;
      sbreadonaddr          = 1'b0;

      // Wait for both DUTs to assert req
      wait (master_req === 1'b1 && master_req_nb === 1'b1);

      // Primary DUT (ReadByteEnable=1) should have BE=0001
      check($sformatf("RBE=1: read BE=%0b expected=0001", master_be),
            master_be === 4'b0001);

      // Second DUT (ReadByteEnable=0) should have BE=0000 (old behavior)
      check($sformatf("RBE=0: read BE=%0b expected=0000", master_be_nb),
            master_be_nb === 4'b0000);

      // Complete the transaction
      @(posedge clk);
      master_gnt = 1'b1;
      @(posedge clk);
      master_gnt = 1'b0;
      master_r_valid = 1'b1;
      master_r_rdata = 32'hABCD1234;
      @(posedge clk);
      master_r_valid = 1'b0;
      wait (sbbusy === 1'b0);
      @(posedge clk);
    end

    // Test ReadByteEnable=0 with halfword read
    begin
      sbaddress             = 32'h0000_0002;
      sbaccess              = 3'b001;  // half access
      sbaddress_write_valid = 1'b1;
      sbreadonaddr          = 1'b1;
      @(posedge clk);
      sbaddress_write_valid = 1'b0;
      sbreadonaddr          = 1'b0;

      wait (master_req === 1'b1 && master_req_nb === 1'b1);
      check($sformatf("RBE=1 half: read BE=%0b expected=1100", master_be),
            master_be === 4'b1100);
      check($sformatf("RBE=0 half: read BE=%0b expected=0000", master_be_nb),
            master_be_nb === 4'b0000);

      @(posedge clk);
      master_gnt = 1'b1;
      @(posedge clk);
      master_gnt = 1'b0;
      master_r_valid = 1'b1;
      master_r_rdata = 32'h0;
      @(posedge clk);
      master_r_valid = 1'b0;
      wait (sbbusy === 1'b0);
      @(posedge clk);
    end

    // Verify writes still have proper BE with ReadByteEnable=0
    begin
      sbaddress          = 32'h0000_0001;
      sbaccess           = 3'b000;
      sbdata             = 32'h0000FF00;
      sbdata_write_valid = 1'b1;
      @(posedge clk);
      sbdata_write_valid = 1'b0;

      wait (master_req_nb === 1'b1);
      check($sformatf("RBE=0 write: BE=%0b expected=0010", master_be_nb),
            master_be_nb === 4'b0010);

      @(posedge clk);
      master_gnt = 1'b1;
      @(posedge clk);
      master_gnt = 1'b0;
      master_r_valid = 1'b1;
      @(posedge clk);
      master_r_valid = 1'b0;
      wait (sbbusy_nb === 1'b0);
      @(posedge clk);
    end

    // ===========================================================
    // TEST GROUP 15: Delayed grant (grant not immediate)
    // ===========================================================
    $display("\n=== TEST GROUP 15: Delayed grant ===");
    begin
      sbaddress             = 32'h0000_0000;
      sbaccess              = 3'b010;
      sbaddress_write_valid = 1'b1;
      sbreadonaddr          = 1'b1;
      @(posedge clk);
      sbaddress_write_valid = 1'b0;
      sbreadonaddr          = 1'b0;

      wait (master_req === 1'b1);
      // Hold grant low for several cycles
      repeat (5) begin
        @(posedge clk);
        check("Req stays high while waiting for grant", master_req === 1'b1);
        check("BE stable while waiting for grant", master_be === 4'b1111);
      end

      // Now grant
      master_gnt = 1'b1;
      @(posedge clk);
      master_gnt = 1'b0;

      // Delay valid response
      repeat (3) @(posedge clk);
      master_r_valid = 1'b1;
      master_r_rdata = 32'hBEEFCAFE;
      @(posedge clk);
      master_r_valid = 1'b0;

      wait (sbbusy === 1'b0);
      check("Data captured after delayed grant/response",
            sbdata_o === 32'hBEEFCAFE);
      @(posedge clk);
    end

    // ===========================================================
    // TEST GROUP 16: Back-to-back transactions
    // ===========================================================
    $display("\n=== TEST GROUP 16: Back-to-back transactions ===");
    begin
      for (int i = 0; i < 4; i++) begin
        do_read_via_addr(32'h0000_0000 + i, 3'b000,
                         4'b0001 << i,
                         32'h10000000 + i,
                         $sformatf("Back-to-back read #%0d", i));
      end
    end

    // ===========================================================
    // Summary
    // ===========================================================
    $display("\n==================================================");
    $display("  TEST SUMMARY: %0d passed, %0d failed out of %0d",
             pass_count, fail_count, pass_count + fail_count);
    $display("==================================================");

    if (fail_count == 0) begin
      $display("PASS: All SBA byte-enable and functionality tests passed.");
    end else begin
      $display("FAIL: %0d test(s) failed.", fail_count);
    end

    $display("Functional Coverage: %.1f%%", cg_inst.get_coverage());
    $finish;
  end

  // ---------------------------------------------------------------------------
  // Patch-focused functional coverage
  // Patch: be_mask applied to reads (not just writes); ReadByteEnable param added
  // ---------------------------------------------------------------------------
  wire               cov_master_we  = master_we;
  wire [BE_WIDTH-1:0] cov_master_be  = master_be;
  wire               cov_master_req = master_req;
  wire [2:0]         cov_sbaccess   = sbaccess;

  covergroup cg_patch;
    cp_sbaccess: coverpoint cov_sbaccess iff (cov_master_req) {
      bins byte_access  = {3'b000};
      bins half_access  = {3'b001};
      bins word_access  = {3'b010};
      // dword (64-bit) access is not possible with BusWidth=32
      ignore_bins dword_access = {3'b011};
    }
    cp_we: coverpoint cov_master_we iff (cov_master_req) {
      bins read  = {1'b0};
      bins write = {1'b1};
    }
    cp_be_nonzero: coverpoint (cov_master_be != '0) iff (cov_master_req) {
      bins be_active   = {1'b1};
      // With ReadByteEnable=1, BE is always non-zero for both reads and writes
      ignore_bins be_inactive = {1'b0};
      illegal_bins bug_read_be_zero = {1'b0} iff (!cov_master_we);
    }
    cx_access_rw: cross cp_sbaccess, cp_we;
  endgroup

  cg_patch cg_inst = new();

  always @(posedge clk) begin
    if (rst_n && master_req) cg_inst.sample();
  end

  // ---------------------------------------------------------------
  // Timeout watchdog
  // ---------------------------------------------------------------
  initial begin
    #100_000;
    $display("TIMEOUT: Simulation exceeded 100us watchdog.");
    $display("FAIL: Simulation timed out.");
    $finish;
  end

  // ---------------------------------------------------------------
  // Waveform dump
  // ---------------------------------------------------------------
  initial begin
    $dumpfile("tb_dm_sba_read_be_patch.vcd");
    $dumpvars(0);
  end

endmodule

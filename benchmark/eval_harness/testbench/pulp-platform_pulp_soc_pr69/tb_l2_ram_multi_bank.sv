`include "soc_mem_map.svh"

module tb_l2_ram_multi_bank;

  //--------------------------------------------------------------------------
  // Parameters
  //--------------------------------------------------------------------------
  localparam int unsigned NB_BANKS            = 4;
  localparam int unsigned BANK_SIZE_INTL_SRAM = 64;  // Small for fast simulation
  localparam int unsigned CLK_PERIOD          = 10;

  //--------------------------------------------------------------------------
  // Clock and reset
  //--------------------------------------------------------------------------
  logic clk_i, rst_ni, init_ni, test_mode_i;

  initial begin
    clk_i = 1'b0;
    forever #(CLK_PERIOD/2) clk_i = ~clk_i;
  end

  //--------------------------------------------------------------------------
  // Signal arrays to drive interfaces (avoids VCS variable-index XMR issue)
  //--------------------------------------------------------------------------
  logic        intl_req   [NB_BANKS];
  logic [31:0] intl_add   [NB_BANKS];
  logic        intl_wen   [NB_BANKS];
  logic [31:0] intl_wdata [NB_BANKS];
  logic [3:0]  intl_be    [NB_BANKS];
  logic        intl_gnt   [NB_BANKS];
  logic        intl_r_valid [NB_BANKS];
  logic [31:0] intl_r_rdata [NB_BANKS];

  logic        pri_req   [2];
  logic [31:0] pri_add   [2];
  logic        pri_wen   [2];
  logic [31:0] pri_wdata [2];
  logic [3:0]  pri_be    [2];
  logic        pri_gnt   [2];
  logic        pri_r_valid [2];
  logic [31:0] pri_r_rdata [2];

  //--------------------------------------------------------------------------
  // Interface instantiations and wiring
  //--------------------------------------------------------------------------
  XBAR_TCDM_BUS mem_slave_if    [NB_BANKS] ();
  XBAR_TCDM_BUS mem_pri_slave_if [2]       ();

  genvar gi;
  generate
    for (gi = 0; gi < NB_BANKS; gi++) begin : GEN_INTL_WIRE
      assign mem_slave_if[gi].req   = intl_req[gi];
      assign mem_slave_if[gi].add   = intl_add[gi];
      assign mem_slave_if[gi].wen   = intl_wen[gi];
      assign mem_slave_if[gi].wdata = intl_wdata[gi];
      assign mem_slave_if[gi].be    = intl_be[gi];
      assign intl_gnt[gi]     = mem_slave_if[gi].gnt;
      assign intl_r_valid[gi] = mem_slave_if[gi].r_valid;
      assign intl_r_rdata[gi] = mem_slave_if[gi].r_rdata;
    end
    for (gi = 0; gi < 2; gi++) begin : GEN_PRI_WIRE
      assign mem_pri_slave_if[gi].req   = pri_req[gi];
      assign mem_pri_slave_if[gi].add   = pri_add[gi];
      assign mem_pri_slave_if[gi].wen   = pri_wen[gi];
      assign mem_pri_slave_if[gi].wdata = pri_wdata[gi];
      assign mem_pri_slave_if[gi].be    = pri_be[gi];
      assign pri_gnt[gi]     = mem_pri_slave_if[gi].gnt;
      assign pri_r_valid[gi] = mem_pri_slave_if[gi].r_valid;
      assign pri_r_rdata[gi] = mem_pri_slave_if[gi].r_rdata;
    end
  endgenerate

  //--------------------------------------------------------------------------
  // DUT
  //--------------------------------------------------------------------------
  l2_ram_multi_bank #(
    .NB_BANKS           (NB_BANKS),
    .BANK_SIZE_INTL_SRAM(BANK_SIZE_INTL_SRAM)
  ) dut (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .init_ni     (init_ni),
    .test_mode_i (test_mode_i),
    .mem_slave   (mem_slave_if),
    .mem_pri_slave(mem_pri_slave_if)
  );

  //--------------------------------------------------------------------------
  // Error counter
  //--------------------------------------------------------------------------
  int error_count = 0;
  int test_count  = 0;

  //--------------------------------------------------------------------------
  // Patch-focused covergroup: PR#69 replaces fpga_interleaved_ram / fpga_private_ram
  // with tc_sram for ALL targets. We cover the key tc_sram interface signals
  // (req, wen, be) and data-integrity scenarios that would fail if the wrong
  // SRAM primitive were instantiated.
  //--------------------------------------------------------------------------
  // Probe interleaved bank 0 and private bank 0 request/grant signals
  wire cov_intl_req   = intl_req[0];
  wire cov_intl_wen   = intl_wen[0];
  wire [3:0] cov_intl_be = intl_be[0];
  wire cov_intl_gnt   = intl_gnt[0];
  wire cov_pri_req    = pri_req[0];
  wire cov_pri_wen    = pri_wen[0];
  wire [3:0] cov_pri_be = pri_be[0];
  wire cov_pri_gnt    = pri_gnt[0];

  covergroup cg_patch;
    option.per_instance = 1;

    // CP1: Interleaved bank request activity
    cp_intl_req: coverpoint cov_intl_req {
      bins idle    = {1'b0};
      bins active  = {1'b1};
    }

    // CP2: Write vs read (wen=0 is write, wen=1 is read)
    cp_intl_wen: coverpoint cov_intl_wen {
      bins write = {1'b0};
      bins read  = {1'b1};
    }

    // CP3: Byte-enable patterns (critical: tc_sram supports be, fpga_interleaved_ram
    //       used a different interface; mismatched be wiring would corrupt data)
    cp_intl_be: coverpoint cov_intl_be {
      bins none      = {4'h0};
      bins partial   = {[4'h1:4'hE]};
      bins all_bytes = {4'hF};
    }

    // CP4: Grant follows request (tc_sram is single-cycle, gnt must track req)
    cp_intl_gnt: coverpoint cov_intl_gnt {
      bins deasserted = {1'b0};
      bins asserted   = {1'b1};
    }

    // CP5: Private bank request activity
    cp_pri_req: coverpoint cov_pri_req {
      bins idle    = {1'b0};
      bins active  = {1'b1};
    }

    // CP6: Private bank write vs read
    cp_pri_wen: coverpoint cov_pri_wen {
      bins write = {1'b0};
      bins read  = {1'b1};
    }

    // CP7: Private bank byte-enables
    cp_pri_be: coverpoint cov_pri_be {
      bins none      = {4'h0};
      bins partial   = {[4'h1:4'hE]};
      bins all_bytes = {4'hF};
    }

    // Cross: interleaved write with byte-enable patterns (the key fix scenario)
    cx_intl_write_be: cross cp_intl_wen, cp_intl_be {
      // be=none with read is an uninteresting state; ignore it
      ignore_bins read_none = binsof(cp_intl_wen.read) && binsof(cp_intl_be.none);
      // Reads always use be=F; partial be on reads never occurs
      ignore_bins read_partial = binsof(cp_intl_wen.read) && binsof(cp_intl_be.partial);
    }

    // Cross: grant must match request (tc_sram gives combinational gnt)
    cx_req_gnt: cross cp_intl_req, cp_intl_gnt {
      // If req=1 but gnt=0, that is the bug behavior (fpga ram had csn inversion)
      illegal_bins bug_req_no_gnt = binsof(cp_intl_req.active) && binsof(cp_intl_gnt.deasserted);
      // gnt is combinational from req; when req=0, gnt=0 always; gnt=1 with req=0 unreachable
      ignore_bins idle_gnt = binsof(cp_intl_req.idle) && binsof(cp_intl_gnt.asserted);
    }

    // Cross: private bank write with byte-enable
    cx_pri_write_be: cross cp_pri_wen, cp_pri_be {
      ignore_bins read_none = binsof(cp_pri_wen.read) && binsof(cp_pri_be.none);
      // Reads always use be=F; partial be on reads never occurs
      ignore_bins read_partial = binsof(cp_pri_wen.read) && binsof(cp_pri_be.partial);
    }
  endgroup

  cg_patch cg_inst = new();

  //--------------------------------------------------------------------------
  // Helper tasks
  //
  // TCDM protocol: 1-cycle latency memory.
  //   gnt = req (combinational)
  //   r_valid registered from req (1 cycle delay)
  //   tc_sram has Latency=1 (rdata available 1 cycle after request)
  //
  // We drive signals at negedge and sample at posedge+#1 to avoid races.
  // Each write/read is a 2-cycle operation: assert req for 1 cycle,
  // then wait for the response cycle.
  //--------------------------------------------------------------------------

  task automatic intl_write(
    input int          bank,
    input logic [31:0] addr,
    input logic [31:0] data,
    input logic [3:0]  be_val
  );
    @(negedge clk_i);
    intl_req[bank]   = 1'b1;
    intl_add[bank]   = addr;
    intl_wen[bank]   = 1'b0;   // wen=0 => write
    intl_wdata[bank] = data;
    intl_be[bank]    = be_val;
    #0; if (bank == 0) cg_inst.sample(); // sample during active request
    @(negedge clk_i);
    intl_req[bank]   = 1'b0;
    intl_wen[bank]   = 1'b1;
    intl_wdata[bank] = 32'h0;
    intl_be[bank]    = 4'h0;
    @(negedge clk_i); // Wait for write to fully complete
  endtask

  task automatic intl_read(
    input  int          bank,
    input  logic [31:0] addr,
    output logic [31:0] rdata
  );
    @(negedge clk_i);
    intl_req[bank] = 1'b1;
    intl_add[bank] = addr;
    intl_wen[bank] = 1'b1;  // wen=1 => read
    intl_be[bank]  = 4'hF;
    #0; if (bank == 0) cg_inst.sample(); // sample during active request
    @(negedge clk_i);
    intl_req[bank] = 1'b0;
    // Data available after the next posedge (tc_sram Latency=1)
    @(posedge clk_i); #1;
    rdata = intl_r_rdata[bank];
  endtask

  task automatic pri_write(
    input int          bank,
    input logic [31:0] addr,
    input logic [31:0] data,
    input logic [3:0]  be_val
  );
    @(negedge clk_i);
    pri_req[bank]   = 1'b1;
    pri_add[bank]   = addr;
    pri_wen[bank]   = 1'b0;
    pri_wdata[bank] = data;
    pri_be[bank]    = be_val;
    #0; if (bank == 0) cg_inst.sample(); // sample during active request
    @(negedge clk_i);
    pri_req[bank]   = 1'b0;
    pri_wen[bank]   = 1'b1;
    pri_wdata[bank] = 32'h0;
    pri_be[bank]    = 4'h0;
    @(negedge clk_i);
  endtask

  task automatic pri_read(
    input  int          bank,
    input  logic [31:0] addr,
    output logic [31:0] rdata
  );
    @(negedge clk_i);
    pri_req[bank] = 1'b1;
    pri_add[bank] = addr;
    pri_wen[bank] = 1'b1;
    pri_be[bank]  = 4'hF;
    #0; if (bank == 0) cg_inst.sample(); // sample during active request
    @(negedge clk_i);
    pri_req[bank] = 1'b0;
    @(posedge clk_i); #1;
    rdata = pri_r_rdata[bank];
  endtask

  task automatic check(
    input string       label,
    input logic [31:0] actual,
    input logic [31:0] expected
  );
    test_count++;
    if (actual !== expected) begin
      $display("ERROR [%s]: expected 0x%08h, got 0x%08h", label, expected, actual);
      error_count++;
    end else begin
      $display("  OK  [%s]: 0x%08h", label, actual);
    end
  endtask

  //--------------------------------------------------------------------------
  // Address computation helpers
  //--------------------------------------------------------------------------
  // TCDM interleaved addressing:
  //   Full addr = TCDM_START + (word_in_bank * NB_BANKS + bank) * 4
  //   bank_sel = addr[3:2] (for NB_BANKS=4), word bits above that
  function automatic logic [31:0] intl_addr(int bank, int word_idx);
    return `SOC_MEM_MAP_TCDM_START_ADDR + (word_idx * NB_BANKS + bank) * 4;
  endfunction

  function automatic logic [31:0] pri0_addr(int word_idx);
    return `SOC_MEM_MAP_PRIVATE_BANK0_START_ADDR + word_idx * 4;
  endfunction

  function automatic logic [31:0] pri1_addr(int word_idx);
    return `SOC_MEM_MAP_PRIVATE_BANK1_START_ADDR + word_idx * 4;
  endfunction

  //--------------------------------------------------------------------------
  // Main stimulus
  //--------------------------------------------------------------------------
  logic [31:0] rdata;
  int i;

  initial begin
    // Initialize signals to idle
    for (i = 0; i < NB_BANKS; i++) begin
      intl_req[i]   = 1'b0;
      intl_add[i]   = 32'h0;
      intl_wen[i]   = 1'b1;
      intl_wdata[i] = 32'h0;
      intl_be[i]    = 4'h0;
    end
    for (i = 0; i < 2; i++) begin
      pri_req[i]   = 1'b0;
      pri_add[i]   = 32'h0;
      pri_wen[i]   = 1'b1;
      pri_wdata[i] = 32'h0;
      pri_be[i]    = 4'h0;
    end

    rst_ni      = 1'b0;
    init_ni     = 1'b0;
    test_mode_i = 1'b0;

    // Hold reset
    repeat (5) @(posedge clk_i);
    @(negedge clk_i);
    rst_ni  = 1'b1;
    init_ni = 1'b1;
    repeat (3) @(posedge clk_i);

    // =================================================================
    // TEST 1: Basic write/read to each interleaved bank
    // =================================================================
    $display("\n=== TEST 1: Basic write/read to each interleaved bank ===");
    for (i = 0; i < NB_BANKS; i++) begin
      intl_write(i, intl_addr(i, 0), 32'hA000_0000 + i, 4'hF);
    end
    for (i = 0; i < NB_BANKS; i++) begin
      intl_read(i, intl_addr(i, 0), rdata);
      check($sformatf("intl_bank%0d_word0", i), rdata, 32'hA000_0000 + i);
    end

    // =================================================================
    // TEST 2: Multiple words in same interleaved bank
    // =================================================================
    $display("\n=== TEST 2: Multiple words in same interleaved bank ===");
    for (i = 0; i < 8; i++) begin
      intl_write(0, intl_addr(0, i), 32'hBEEF_0000 + i, 4'hF);
    end
    for (i = 0; i < 8; i++) begin
      intl_read(0, intl_addr(0, i), rdata);
      check($sformatf("intl_bank0_word%0d", i), rdata, 32'hBEEF_0000 + i);
    end

    // =================================================================
    // TEST 3: Byte-enable partial writes (each byte lane individually)
    // =================================================================
    $display("\n=== TEST 3: Byte-enable partial writes ===");
    intl_write(1, intl_addr(1, 0), 32'hFFFF_FFFF, 4'hF);

    intl_write(1, intl_addr(1, 0), 32'h0000_00AA, 4'h1);
    intl_read(1, intl_addr(1, 0), rdata);
    check("be_byte0", rdata, 32'hFFFF_FFAA);

    intl_write(1, intl_addr(1, 0), 32'h0000_BB00, 4'h2);
    intl_read(1, intl_addr(1, 0), rdata);
    check("be_byte1", rdata, 32'hFFFF_BBAA);

    intl_write(1, intl_addr(1, 0), 32'h00CC_0000, 4'h4);
    intl_read(1, intl_addr(1, 0), rdata);
    check("be_byte2", rdata, 32'hFFCC_BBAA);

    intl_write(1, intl_addr(1, 0), 32'hDD00_0000, 4'h8);
    intl_read(1, intl_addr(1, 0), rdata);
    check("be_byte3", rdata, 32'hDDCC_BBAA);

    // Overwrite bytes 0 and 2 simultaneously
    intl_write(1, intl_addr(1, 0), 32'h0011_0022, 4'h5);
    intl_read(1, intl_addr(1, 0), rdata);
    check("be_byte0_2", rdata, 32'hDD11_BB22);

    // =================================================================
    // TEST 4: Private bank 0 write/read
    // =================================================================
    $display("\n=== TEST 4: Private bank 0 ===");
    for (i = 0; i < 8; i++) begin
      pri_write(0, pri0_addr(i), 32'hCAFE_0000 + i, 4'hF);
    end
    for (i = 0; i < 8; i++) begin
      pri_read(0, pri0_addr(i), rdata);
      check($sformatf("pri0_word%0d", i), rdata, 32'hCAFE_0000 + i);
    end

    // =================================================================
    // TEST 5: Private bank 1 write/read
    // =================================================================
    $display("\n=== TEST 5: Private bank 1 ===");
    for (i = 0; i < 8; i++) begin
      pri_write(1, pri1_addr(i), 32'hDEAD_0000 + i, 4'hF);
    end
    for (i = 0; i < 8; i++) begin
      pri_read(1, pri1_addr(i), rdata);
      check($sformatf("pri1_word%0d", i), rdata, 32'hDEAD_0000 + i);
    end

    // =================================================================
    // TEST 6: Byte-enable on private banks
    // =================================================================
    $display("\n=== TEST 6: Byte-enable on private banks ===");
    pri_write(0, pri0_addr(0), 32'h1234_5678, 4'hF);
    pri_write(0, pri0_addr(0), 32'hABCD_0000, 4'hC);
    pri_read(0, pri0_addr(0), rdata);
    check("pri0_be_upper", rdata, 32'hABCD_5678);

    pri_write(1, pri1_addr(0), 32'h8765_4321, 4'hF);
    pri_write(1, pri1_addr(0), 32'h0000_FFEE, 4'h3);
    pri_read(1, pri1_addr(0), rdata);
    check("pri1_be_lower", rdata, 32'h8765_FFEE);

    // =================================================================
    // TEST 7: Grant is combinational (gnt = req)
    // =================================================================
    $display("\n=== TEST 7: Grant behavior ===");
    // With req=0, gnt must be 0
    test_count++;
    if (intl_gnt[0] !== 1'b0) begin
      $display("ERROR [gnt_idle]: gnt should be 0 when req is 0");
      error_count++;
    end else begin
      $display("  OK  [gnt_idle]: gnt is 0 when req is 0");
    end
    // Assert req and check gnt combinationally
    @(negedge clk_i);
    intl_req[0] = 1'b1;
    intl_add[0] = intl_addr(0, 0);
    intl_wen[0] = 1'b1;
    #1;
    test_count++;
    if (intl_gnt[0] !== 1'b1) begin
      $display("ERROR [gnt_active]: gnt should be 1 when req is 1");
      error_count++;
    end else begin
      $display("  OK  [gnt_active]: gnt is 1 when req is 1");
    end
    intl_req[0] = 1'b0;
    @(posedge clk_i);

    // =================================================================
    // TEST 8: All-zeros and all-ones data patterns
    // =================================================================
    $display("\n=== TEST 8: Data patterns ===");
    intl_write(2, intl_addr(2, 5), 32'h0000_0000, 4'hF);
    intl_read(2, intl_addr(2, 5), rdata);
    check("all_zeros", rdata, 32'h0000_0000);

    intl_write(2, intl_addr(2, 5), 32'hFFFF_FFFF, 4'hF);
    intl_read(2, intl_addr(2, 5), rdata);
    check("all_ones", rdata, 32'hFFFF_FFFF);

    // =================================================================
    // TEST 9: Checkerboard patterns
    // =================================================================
    $display("\n=== TEST 9: Checkerboard patterns ===");
    intl_write(3, intl_addr(3, 0), 32'h5555_5555, 4'hF);
    intl_read(3, intl_addr(3, 0), rdata);
    check("checker_55", rdata, 32'h5555_5555);

    intl_write(3, intl_addr(3, 1), 32'hAAAA_AAAA, 4'hF);
    intl_read(3, intl_addr(3, 1), rdata);
    check("checker_AA", rdata, 32'hAAAA_AAAA);

    // =================================================================
    // TEST 10: Reset clears r_valid
    // =================================================================
    $display("\n=== TEST 10: Reset clears r_valid ===");
    // Do a request to get r_valid active
    @(negedge clk_i);
    intl_req[0] = 1'b1;
    intl_add[0] = intl_addr(0, 0);
    intl_wen[0] = 1'b1;
    @(negedge clk_i);
    intl_req[0] = 1'b0;
    // Assert reset
    @(negedge clk_i);
    rst_ni = 1'b0;
    repeat (3) @(posedge clk_i);
    #1;
    test_count++;
    if (intl_r_valid[0] !== 1'b0) begin
      $display("ERROR [reset_rvalid]: r_valid should be 0 during reset");
      error_count++;
    end else begin
      $display("  OK  [reset_rvalid]: r_valid is 0 during reset");
    end
    test_count++;
    if (pri_r_valid[0] !== 1'b0 || pri_r_valid[1] !== 1'b0) begin
      $display("ERROR [reset_pri_rvalid]: private bank r_valid should be 0 during reset");
      error_count++;
    end else begin
      $display("  OK  [reset_pri_rvalid]: private bank r_valid is 0 during reset");
    end
    @(negedge clk_i);
    rst_ni = 1'b1;
    repeat (3) @(posedge clk_i);

    // =================================================================
    // TEST 11: Data persistence across idle cycles
    // =================================================================
    $display("\n=== TEST 11: Data persistence ===");
    intl_write(0, intl_addr(0, 10), 32'hFACE_B00C, 4'hF);
    repeat (10) @(posedge clk_i);
    intl_read(0, intl_addr(0, 10), rdata);
    check("persist_idle", rdata, 32'hFACE_B00C);

    // =================================================================
    // TEST 12: Back-to-back writes then reads
    // =================================================================
    $display("\n=== TEST 12: Back-to-back operations ===");
    for (i = 0; i < 4; i++) begin
      intl_write(0, intl_addr(0, 20+i), 32'hB0B0_0000 + i, 4'hF);
    end
    for (i = 0; i < 4; i++) begin
      intl_read(0, intl_addr(0, 20+i), rdata);
      check($sformatf("b2b_word%0d", i), rdata, 32'hB0B0_0000 + i);
    end

    // =================================================================
    // TEST 12b: Partial byte-enable write on bank 0 (for coverage)
    // =================================================================
    $display("\n=== TEST 12b: Partial byte-enable on bank 0 ===");
    intl_write(0, intl_addr(0, 25), 32'hFFFF_FFFF, 4'hF);
    intl_write(0, intl_addr(0, 25), 32'hAA00_BB00, 4'h5);
    intl_read(0, intl_addr(0, 25), rdata);
    check("b0_partial_be", rdata, 32'hFF00_FF00);

    // =================================================================
    // TEST 13: Write with be=0 should NOT modify data
    // =================================================================
    $display("\n=== TEST 13: Write with be=0 (no-op) ===");
    intl_write(2, intl_addr(2, 3), 32'h1111_2222, 4'hF);
    intl_write(2, intl_addr(2, 3), 32'hDEAD_BEEF, 4'h0);
    intl_read(2, intl_addr(2, 3), rdata);
    check("be_zero_noop", rdata, 32'h1111_2222);

    // Also test be=0 on bank 0 for coverage
    intl_write(0, intl_addr(0, 26), 32'h5555_6666, 4'hF);
    intl_write(0, intl_addr(0, 26), 32'hDEAD_BEEF, 4'h0);
    intl_read(0, intl_addr(0, 26), rdata);
    check("b0_be_zero_noop", rdata, 32'h5555_6666);

    // And be=0 on private bank 0 for coverage
    pri_write(0, pri0_addr(7), 32'hAAAA_BBBB, 4'hF);
    pri_write(0, pri0_addr(7), 32'hDEAD_BEEF, 4'h0);
    pri_read(0, pri0_addr(7), rdata);
    check("pri0_be_zero_noop", rdata, 32'hAAAA_BBBB);

    // =================================================================
    // TEST 14: Bank independence (interleaved)
    // =================================================================
    $display("\n=== TEST 14: Bank independence ===");
    for (i = 0; i < NB_BANKS; i++) begin
      intl_write(i, intl_addr(i, 2), 32'hF000_0000 + i * 32'h0100_0000, 4'hF);
    end
    for (i = 0; i < NB_BANKS; i++) begin
      intl_read(i, intl_addr(i, 2), rdata);
      check($sformatf("indep_bank%0d", i), rdata, 32'hF000_0000 + i * 32'h0100_0000);
    end

    // =================================================================
    // TEST 14b: Partial byte-enable write on private bank 0 (for coverage)
    // =================================================================
    $display("\n=== TEST 14b: Partial byte-enable on private bank 0 ===");
    pri_write(0, pri0_addr(6), 32'hFFFF_FFFF, 4'hF);
    pri_write(0, pri0_addr(6), 32'h0000_AA00, 4'h2);
    pri_read(0, pri0_addr(6), rdata);
    check("pri0_partial_be", rdata, 32'hFFFF_AAFF);

    // =================================================================
    // TEST 15: Private bank independence
    // =================================================================
    $display("\n=== TEST 15: Private bank independence ===");
    pri_write(0, pri0_addr(5), 32'h1111_1111, 4'hF);
    pri_write(1, pri1_addr(5), 32'h2222_2222, 4'hF);
    pri_read(0, pri0_addr(5), rdata);
    check("pri0_indep", rdata, 32'h1111_1111);
    pri_read(1, pri1_addr(5), rdata);
    check("pri1_indep", rdata, 32'h2222_2222);

    // =================================================================
    // TEST 16: Walking ones pattern (catches stuck data bits)
    // =================================================================
    $display("\n=== TEST 16: Walking ones ===");
    for (i = 0; i < 32; i++) begin
      intl_write(0, intl_addr(0, 30), 32'h1 << i, 4'hF);
      intl_read(0, intl_addr(0, 30), rdata);
      check($sformatf("walk1_bit%0d", i), rdata, 32'h1 << i);
    end

    // =================================================================
    // TEST 17: Repeated overwrite same address
    // =================================================================
    $display("\n=== TEST 17: Repeated overwrite ===");
    for (i = 0; i < 10; i++) begin
      intl_write(1, intl_addr(1, 7), i, 4'hF);
    end
    intl_read(1, intl_addr(1, 7), rdata);
    check("overwrite_final", rdata, 32'd9);

    // =================================================================
    // TEST 18: r_opc is always 0 (hardwired)
    // =================================================================
    $display("\n=== TEST 18: r_opc always 0 ===");
    test_count++;
    if (mem_slave_if[0].r_opc !== 1'b0) begin
      $display("ERROR [r_opc_intl]: r_opc should always be 0");
      error_count++;
    end else begin
      $display("  OK  [r_opc_intl]: r_opc is 0");
    end
    test_count++;
    if (mem_pri_slave_if[0].r_opc !== 1'b0) begin
      $display("ERROR [r_opc_pri0]: r_opc should always be 0");
      error_count++;
    end else begin
      $display("  OK  [r_opc_pri0]: r_opc is 0");
    end
    test_count++;
    if (mem_pri_slave_if[1].r_opc !== 1'b0) begin
      $display("ERROR [r_opc_pri1]: r_opc should always be 0");
      error_count++;
    end else begin
      $display("  OK  [r_opc_pri1]: r_opc is 0");
    end

    // =================================================================
    // TEST 19: Interleaved and private banks do not alias
    //          (writing to interleaved does not corrupt private and vice versa)
    // =================================================================
    $display("\n=== TEST 19: No aliasing between interleaved and private ===");
    pri_write(0, pri0_addr(0), 32'hAAAA_BBBB, 4'hF);
    intl_write(0, intl_addr(0, 0), 32'hCCCC_DDDD, 4'hF);
    pri_read(0, pri0_addr(0), rdata);
    check("no_alias_pri0", rdata, 32'hAAAA_BBBB);
    intl_read(0, intl_addr(0, 0), rdata);
    check("no_alias_intl0", rdata, 32'hCCCC_DDDD);

    // =================================================================
    // TEST 20: Half-word byte enables (upper and lower)
    // =================================================================
    $display("\n=== TEST 20: Half-word byte enables ===");
    intl_write(3, intl_addr(3, 4), 32'h0000_0000, 4'hF);
    intl_write(3, intl_addr(3, 4), 32'hAABB_CCDD, 4'h3);  // lower half
    intl_read(3, intl_addr(3, 4), rdata);
    check("halfword_lower", rdata, 32'h0000_CCDD);

    intl_write(3, intl_addr(3, 4), 32'h0000_0000, 4'hF);
    intl_write(3, intl_addr(3, 4), 32'hAABB_CCDD, 4'hC);  // upper half
    intl_read(3, intl_addr(3, 4), rdata);
    check("halfword_upper", rdata, 32'hAABB_0000);

    // =================================================================
    // Sample coverage after all tests
    // =================================================================
    cg_inst.sample();

    // =================================================================
    // Summary
    // =================================================================
    repeat (5) @(posedge clk_i);
    $display("\n========================================");
    $display("  Tests run:    %0d", test_count);
    $display("  Errors:       %0d", error_count);
    if (error_count == 0) begin
      $display("  RESULT: PASS");
    end else begin
      $display("  RESULT: FAIL");
    end
    $display("========================================");
    $display("Functional Coverage: %.1f%%", cg_inst.get_coverage());
    $display("========================================\n");
    $finish;
  end

  // Timeout watchdog
  initial begin
    #(CLK_PERIOD * 100000);
    $display("ERROR: Simulation timed out!");
    $display("RESULT: FAIL");
    $finish;
  end

endmodule

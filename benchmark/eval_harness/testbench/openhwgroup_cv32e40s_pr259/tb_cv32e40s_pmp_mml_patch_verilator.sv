// Testbench for cv32e40s_pmp - Issue 249 / PR 259
//
// The bug: when PMP_NUM_REGIONS == 0, pmp_req_err_o was tied to 0 regardless
// of mseccfg settings. The default-deny logic in access_fault correctly handles
// MMWP and non-M privilege levels, but the final output gated it away for 0
// regions via: (PMP_NUM_REGIONS == 0) ? 1'b0 : access_fault
//
// The fix: assign pmp_req_err_o = access_fault (always, not gated by region count).
//
// The default-deny logic is:
//   access_fault = mseccfg.mmwp || (priv_lvl != M)
// So with 0 regions:
//   - MMWP=1 => always denied (any mode) -- broken pre-patch
//   - U-mode => denied -- broken pre-patch
//   - M-mode without MMWP => allowed (access_fault=0)
//
// This testbench exercises:
//   Part 1: PMP_NUM_REGIONS=0 -- validates the bug fix
//   Part 2: PMP_NUM_REGIONS=4 -- validates region matching, MML, MMWP, priority

module tb_cv32e40s_pmp_mml_patch;

  import cv32e40s_pkg::*;

  logic        clk = 0;
  logic        rst_n;

  // DUT signals for 0-region instance
  pmp_csr_t    csr_pmp_0;
  privlvl_t    priv_lvl_0;
  logic [33:0] pmp_req_addr_0;
  pmp_req_e    pmp_req_type_0;
  logic        pmp_req_err_0;

  // DUT signals for 4-region instance
  pmp_csr_t    csr_pmp_4;
  privlvl_t    priv_lvl_4;
  logic [33:0] pmp_req_addr_4;
  pmp_req_e    pmp_req_type_4;
  logic        pmp_req_err_4;

  // Instantiate PMP with 0 regions (the bug scenario)
  cv32e40s_pmp #(
    .PMP_GRANULARITY(0),
    .PMP_NUM_REGIONS(0)
  ) dut_0reg (
    .clk            (clk),
    .rst_n          (rst_n),
    .csr_pmp_i      (csr_pmp_0),
    .priv_lvl_i     (priv_lvl_0),
    .pmp_req_addr_i (pmp_req_addr_0),
    .pmp_req_type_i (pmp_req_type_0),
    .pmp_req_err_o  (pmp_req_err_0)
  );

  // Instantiate PMP with 4 regions for region-matching tests
  cv32e40s_pmp #(
    .PMP_GRANULARITY(0),
    .PMP_NUM_REGIONS(4)
  ) dut_4reg (
    .clk            (clk),
    .rst_n          (rst_n),
    .csr_pmp_i      (csr_pmp_4),
    .priv_lvl_i     (priv_lvl_4),
    .pmp_req_addr_i (pmp_req_addr_4),
    .pmp_req_type_i (pmp_req_type_4),
    .pmp_req_err_o  (pmp_req_err_4)
  );

  always #5 clk = ~clk;

  integer pass_count = 0;
  integer fail_count = 0;
  integer test_num   = 0;

  // ---- Patch-focused coverage ----
  // [verilator-strip cg] covergroup cg_patch;
// [verilator-strip cg]     cp_err_0reg:   coverpoint pmp_req_err_0;
// [verilator-strip cg]     cp_err_4reg:   coverpoint pmp_req_err_4;
// [verilator-strip cg]     cp_priv_0:     coverpoint priv_lvl_0 { bins m = {PRIV_LVL_M}; bins u = {PRIV_LVL_U}; }
// [verilator-strip cg]     cp_priv_4:     coverpoint priv_lvl_4 { bins m = {PRIV_LVL_M}; bins u = {PRIV_LVL_U}; }
// [verilator-strip cg]     cp_mmwp_0:     coverpoint csr_pmp_0.mseccfg.mmwp;
// [verilator-strip cg]     cp_req_type_0: coverpoint pmp_req_type_0 {
// [verilator-strip cg]       bins read = {PMP_ACC_READ}; bins write = {PMP_ACC_WRITE}; bins exec = {PMP_ACC_EXEC};
// [verilator-strip cg]     }
// [verilator-strip cg]     cx_0reg_bug:   cross cp_priv_0, cp_mmwp_0, cp_err_0reg {
// [verilator-strip cg]       illegal_bins bug_no_deny = binsof(cp_priv_0) intersect {PRIV_LVL_U}
// [verilator-strip cg]         && binsof(cp_err_0reg) intersect {0};
// [verilator-strip cg]       // M-mode, mmwp=0, 0 regions: always allowed (err=0); err=1 unreachable
// [verilator-strip cg]       ignore_bins m_mmwp0_err1 = binsof(cp_priv_0) intersect {PRIV_LVL_M}
// [verilator-strip cg]         && binsof(cp_mmwp_0) intersect {0}
// [verilator-strip cg]         && binsof(cp_err_0reg) intersect {1};
// [verilator-strip cg]       // M-mode, mmwp=1, 0 regions: always denied (err=1); err=0 unreachable
// [verilator-strip cg]       ignore_bins m_mmwp1_err0 = binsof(cp_priv_0) intersect {PRIV_LVL_M}
// [verilator-strip cg]         && binsof(cp_mmwp_0) intersect {1}
// [verilator-strip cg]         && binsof(cp_err_0reg) intersect {0};
// [verilator-strip cg]     }
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_patch cg_inst = new();

  task check(input string desc, input logic actual, input logic expected);
    test_num = test_num + 1;
    /* [verilator-strip sample] */;
    if (actual === expected) begin
      $display("  [PASS] Test %0d: %s (err=%0b)", test_num, desc, actual);
      pass_count = pass_count + 1;
    end else begin
      $display("  [FAIL] Test %0d: %s (expected err=%0b, got err=%0b)", test_num, desc, expected, actual);
      fail_count = fail_count + 1;
    end
  endtask

  // Helper: initialize 0-region DUT to defaults
  task reset_0reg;
    csr_pmp_0       = '0;
    priv_lvl_0      = PRIV_LVL_M;
    pmp_req_addr_0  = 34'h0;
    pmp_req_type_0  = PMP_ACC_EXEC;
  endtask

  // Helper: initialize 4-region DUT to defaults
  task reset_4reg;
    csr_pmp_4       = '0;
    priv_lvl_4      = PRIV_LVL_M;
    pmp_req_addr_4  = 34'h0;
    pmp_req_type_4  = PMP_ACC_EXEC;
  endtask

  initial begin
    rst_n = 0;
    reset_0reg();
    reset_4reg();
    #20;
    rst_n = 1;
    #10;

    // =========================================================================
    // PART 1: PMP_NUM_REGIONS = 0 (the bug scenario)
    //
    // Default-deny: access_fault = mmwp || (priv_lvl != M)
    // Pre-patch bug: pmp_req_err_o forced to 0 when PMP_NUM_REGIONS==0
    // Post-patch: pmp_req_err_o = access_fault
    // =========================================================================
    $display("\n=== Part 1: PMP_NUM_REGIONS=0, default-deny tests ===");

    // ---- MMWP=1: default deny for all modes, all access types ----
    $display("\n--- MMWP=1, M-mode, 0 regions (should deny) ---");
    reset_0reg();
    csr_pmp_0.mseccfg.mmwp = 1'b1;
    priv_lvl_0 = PRIV_LVL_M;

    pmp_req_type_0 = PMP_ACC_EXEC;
    pmp_req_addr_0 = 34'h0000_1000;
    #1;
    check("MMWP=1, M-mode, EXEC denied", pmp_req_err_0, 1'b1);

    pmp_req_type_0 = PMP_ACC_READ;
    #1;
    check("MMWP=1, M-mode, READ denied", pmp_req_err_0, 1'b1);

    pmp_req_type_0 = PMP_ACC_WRITE;
    #1;
    check("MMWP=1, M-mode, WRITE denied", pmp_req_err_0, 1'b1);

    $display("\n--- MMWP=1, U-mode, 0 regions (should deny) ---");
    priv_lvl_0 = PRIV_LVL_U;

    pmp_req_type_0 = PMP_ACC_EXEC;
    #1;
    check("MMWP=1, U-mode, EXEC denied", pmp_req_err_0, 1'b1);

    pmp_req_type_0 = PMP_ACC_READ;
    #1;
    check("MMWP=1, U-mode, READ denied", pmp_req_err_0, 1'b1);

    pmp_req_type_0 = PMP_ACC_WRITE;
    #1;
    check("MMWP=1, U-mode, WRITE denied", pmp_req_err_0, 1'b1);

    // ---- MMWP=1, MML=1: still denied ----
    $display("\n--- MMWP=1, MML=1, M-mode, 0 regions ---");
    reset_0reg();
    csr_pmp_0.mseccfg.mmwp = 1'b1;
    csr_pmp_0.mseccfg.mml  = 1'b1;
    priv_lvl_0 = PRIV_LVL_M;

    pmp_req_type_0 = PMP_ACC_EXEC;
    #1;
    check("MMWP=1+MML=1, M-mode, EXEC denied", pmp_req_err_0, 1'b1);

    pmp_req_type_0 = PMP_ACC_READ;
    #1;
    check("MMWP=1+MML=1, M-mode, READ denied", pmp_req_err_0, 1'b1);

    pmp_req_type_0 = PMP_ACC_WRITE;
    #1;
    check("MMWP=1+MML=1, M-mode, WRITE denied", pmp_req_err_0, 1'b1);

    // ---- No MMWP, U-mode: denied by default (priv != M) ----
    $display("\n--- MMWP=0, MML=0, U-mode, 0 regions (should deny) ---");
    reset_0reg();
    priv_lvl_0 = PRIV_LVL_U;

    pmp_req_type_0 = PMP_ACC_EXEC;
    #1;
    check("No flags, U-mode, EXEC denied (default)", pmp_req_err_0, 1'b1);

    pmp_req_type_0 = PMP_ACC_READ;
    #1;
    check("No flags, U-mode, READ denied (default)", pmp_req_err_0, 1'b1);

    pmp_req_type_0 = PMP_ACC_WRITE;
    #1;
    check("No flags, U-mode, WRITE denied (default)", pmp_req_err_0, 1'b1);

    // ---- MML=1 only, U-mode: denied (priv != M) ----
    $display("\n--- MML=1, MMWP=0, U-mode, 0 regions ---");
    reset_0reg();
    csr_pmp_0.mseccfg.mml = 1'b1;
    priv_lvl_0 = PRIV_LVL_U;

    pmp_req_type_0 = PMP_ACC_EXEC;
    #1;
    check("MML=1, U-mode, EXEC denied", pmp_req_err_0, 1'b1);

    pmp_req_type_0 = PMP_ACC_READ;
    #1;
    check("MML=1, U-mode, READ denied", pmp_req_err_0, 1'b1);

    // ---- MMWP=1, various addresses: all denied ----
    $display("\n--- MMWP=1, M-mode, different addresses ---");
    reset_0reg();
    csr_pmp_0.mseccfg.mmwp = 1'b1;
    priv_lvl_0 = PRIV_LVL_M;
    pmp_req_type_0 = PMP_ACC_EXEC;

    pmp_req_addr_0 = 34'h0_0000_0000;
    #1;
    check("MMWP=1, EXEC @ addr 0x0", pmp_req_err_0, 1'b1);

    pmp_req_addr_0 = 34'h0_8000_0000;
    #1;
    check("MMWP=1, EXEC @ addr 0x80000000", pmp_req_err_0, 1'b1);

    pmp_req_addr_0 = 34'h3_FFFF_FFFC;
    #1;
    check("MMWP=1, EXEC @ addr 0x3FFFFFFFC (max)", pmp_req_err_0, 1'b1);

    // ---- Baseline: M-mode, no MMWP, no MML => allowed (access_fault=0) ----
    $display("\n--- No flags, M-mode, 0 regions (allowed - baseline) ---");
    reset_0reg();
    priv_lvl_0 = PRIV_LVL_M;

    pmp_req_type_0 = PMP_ACC_EXEC;
    #1;
    check("No flags, M-mode, EXEC allowed", pmp_req_err_0, 1'b0);

    pmp_req_type_0 = PMP_ACC_READ;
    #1;
    check("No flags, M-mode, READ allowed", pmp_req_err_0, 1'b0);

    pmp_req_type_0 = PMP_ACC_WRITE;
    #1;
    check("No flags, M-mode, WRITE allowed", pmp_req_err_0, 1'b0);

    // ---- MML=1 only, M-mode, no MMWP => allowed ----
    // (MML does not affect the default-deny logic, only region permission checks)
    $display("\n--- MML=1, MMWP=0, M-mode, 0 regions (allowed) ---");
    reset_0reg();
    csr_pmp_0.mseccfg.mml = 1'b1;
    priv_lvl_0 = PRIV_LVL_M;

    pmp_req_type_0 = PMP_ACC_EXEC;
    #1;
    check("MML=1, M-mode, EXEC allowed (no MMWP, default allow)", pmp_req_err_0, 1'b0);

    pmp_req_type_0 = PMP_ACC_READ;
    #1;
    check("MML=1, M-mode, READ allowed (no MMWP, default allow)", pmp_req_err_0, 1'b0);

    // =========================================================================
    // PART 2: PMP_NUM_REGIONS = 4 (region matching + MML behavior)
    // =========================================================================
    $display("\n=== Part 2: PMP_NUM_REGIONS=4, region matching tests ===");

    // ---- Standard PMP: TOR region, M-mode unlocked ----
    $display("\n--- Standard PMP (no MML), M-mode, TOR region ---");
    reset_4reg();
    csr_pmp_4.cfg[0].mode  = PMP_MODE_TOR;
    csr_pmp_4.cfg[0].read  = 1'b1;
    csr_pmp_4.cfg[0].write = 1'b0;
    csr_pmp_4.cfg[0].exec  = 1'b1;
    csr_pmp_4.cfg[0].lock  = 1'b0;
    csr_pmp_4.addr[0]      = 34'h0000_2000;
    priv_lvl_4 = PRIV_LVL_M;

    // M-mode, unlocked: all access types allowed (M-mode ignores permissions when not locked)
    pmp_req_type_4 = PMP_ACC_EXEC;
    pmp_req_addr_4 = 34'h0000_1000;
    #1;
    check("TOR region, M-mode, unlocked, EXEC allowed", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_WRITE;
    #1;
    check("TOR region, M-mode, unlocked, WRITE allowed", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("TOR region, M-mode, unlocked, READ allowed", pmp_req_err_4, 1'b0);

    // Address outside TOR region: M-mode, no MMWP => allowed
    pmp_req_addr_4 = 34'h0000_3000;
    pmp_req_type_4 = PMP_ACC_EXEC;
    #1;
    check("Outside TOR region, M-mode, EXEC allowed (no MMWP)", pmp_req_err_4, 1'b0);

    // ---- Standard PMP: TOR region, U-mode ----
    $display("\n--- Standard PMP (no MML), U-mode, TOR region ---");
    priv_lvl_4 = PRIV_LVL_U;
    pmp_req_addr_4 = 34'h0000_1000;

    pmp_req_type_4 = PMP_ACC_EXEC;
    #1;
    check("TOR region, U-mode, EXEC allowed (X=1)", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("TOR region, U-mode, READ allowed (R=1)", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_WRITE;
    #1;
    check("TOR region, U-mode, WRITE denied (W=0)", pmp_req_err_4, 1'b1);

    // U-mode outside region: denied (no matching region)
    pmp_req_addr_4 = 34'h0000_3000;
    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("Outside TOR region, U-mode, READ denied", pmp_req_err_4, 1'b1);

    // ---- Locked region restricts M-mode ----
    $display("\n--- Standard PMP, locked region, M-mode ---");
    reset_4reg();
    csr_pmp_4.cfg[0].mode  = PMP_MODE_TOR;
    csr_pmp_4.cfg[0].read  = 1'b1;
    csr_pmp_4.cfg[0].write = 1'b0;
    csr_pmp_4.cfg[0].exec  = 1'b0;
    csr_pmp_4.cfg[0].lock  = 1'b1;
    csr_pmp_4.addr[0]      = 34'h0000_2000;
    priv_lvl_4 = PRIV_LVL_M;

    pmp_req_addr_4 = 34'h0000_1000;

    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("Locked TOR, M-mode, READ allowed (R=1)", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_EXEC;
    #1;
    check("Locked TOR, M-mode, EXEC denied (X=0, locked)", pmp_req_err_4, 1'b1);

    pmp_req_type_4 = PMP_ACC_WRITE;
    #1;
    check("Locked TOR, M-mode, WRITE denied (W=0, locked)", pmp_req_err_4, 1'b1);

    // ---- MML=1 with matching locked NAPOT region (M-mode rule) ----
    $display("\n--- MML=1, locked region (M-mode rule), NAPOT ---");
    reset_4reg();
    csr_pmp_4.mseccfg.mml = 1'b1;
    // NAPOT 16KB at 0: addr[13:2] all 1s
    csr_pmp_4.cfg[0].mode  = PMP_MODE_NAPOT;
    csr_pmp_4.cfg[0].read  = 1'b1;
    csr_pmp_4.cfg[0].write = 1'b0;
    csr_pmp_4.cfg[0].exec  = 1'b1;
    csr_pmp_4.cfg[0].lock  = 1'b1; // Lock = M-mode rule in MML mode
    csr_pmp_4.addr[0]      = {20'h0, 12'hFFF, 2'b00};
    priv_lvl_4 = PRIV_LVL_M;

    pmp_req_addr_4 = 34'h0000_1000;

    pmp_req_type_4 = PMP_ACC_EXEC;
    #1;
    check("MML=1, locked NAPOT, M-mode, EXEC allowed (L=1,R=1,X=1)", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("MML=1, locked NAPOT, M-mode, READ allowed (L=1,R=1)", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_WRITE;
    #1;
    check("MML=1, locked NAPOT, M-mode, WRITE denied (L=1,W=0)", pmp_req_err_4, 1'b1);

    // U-mode accessing M-mode rule: denied
    priv_lvl_4 = PRIV_LVL_U;
    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("MML=1, locked NAPOT, U-mode, READ denied (M-mode rule)", pmp_req_err_4, 1'b1);

    // ---- MML=1, unlocked region (S/U-mode rule) ----
    $display("\n--- MML=1, unlocked region (S/U-mode rule) ---");
    reset_4reg();
    csr_pmp_4.mseccfg.mml = 1'b1;
    csr_pmp_4.cfg[0].mode  = PMP_MODE_NAPOT;
    csr_pmp_4.cfg[0].read  = 1'b1;
    csr_pmp_4.cfg[0].write = 1'b1;
    csr_pmp_4.cfg[0].exec  = 1'b0;
    csr_pmp_4.cfg[0].lock  = 1'b0; // Unlocked = S/U-mode rule
    csr_pmp_4.addr[0]      = {20'h0, 12'hFFF, 2'b00};

    priv_lvl_4 = PRIV_LVL_U;
    pmp_req_addr_4 = 34'h0000_1000;

    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("MML=1, unlocked, U-mode, READ allowed (L=0,R=1)", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_WRITE;
    #1;
    check("MML=1, unlocked, U-mode, WRITE allowed (L=0,W=1)", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_EXEC;
    #1;
    check("MML=1, unlocked, U-mode, EXEC denied (L=0,X=0)", pmp_req_err_4, 1'b1);

    // M-mode accessing S/U-mode rule: denied
    priv_lvl_4 = PRIV_LVL_M;
    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("MML=1, unlocked, M-mode, READ denied (S/U rule)", pmp_req_err_4, 1'b1);

    // ---- MML=1, no matching region, M-mode, no MMWP: default allows ----
    // (MML only affects per-region permission checks, not the default-deny)
    $display("\n--- MML=1, address outside all regions, no MMWP ---");
    reset_4reg();
    csr_pmp_4.mseccfg.mml = 1'b1;
    csr_pmp_4.cfg[0].mode  = PMP_MODE_NAPOT;
    csr_pmp_4.cfg[0].read  = 1'b1;
    csr_pmp_4.cfg[0].write = 1'b1;
    csr_pmp_4.cfg[0].exec  = 1'b1;
    csr_pmp_4.cfg[0].lock  = 1'b1;
    csr_pmp_4.addr[0]      = {20'h0, 12'hFFF, 2'b00}; // 16KB at 0

    priv_lvl_4 = PRIV_LVL_M;
    pmp_req_addr_4 = 34'h0001_0000; // Outside the NAPOT region

    pmp_req_type_4 = PMP_ACC_EXEC;
    #1;
    check("MML=1, outside region, M-mode, EXEC allowed (default, no MMWP)", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("MML=1, outside region, M-mode, READ allowed (default, no MMWP)", pmp_req_err_4, 1'b0);

    // U-mode outside region: denied (priv != M)
    priv_lvl_4 = PRIV_LVL_U;
    pmp_req_type_4 = PMP_ACC_EXEC;
    #1;
    check("MML=1, outside region, U-mode, EXEC denied", pmp_req_err_4, 1'b1);

    // ---- MML shared region (R=0, W=1, L=0, X=0): RW in M, R only in S/U ----
    $display("\n--- MML=1, shared (R=0,W=1,L=0,X=0): RW M, R S/U ---");
    reset_4reg();
    csr_pmp_4.mseccfg.mml = 1'b1;
    csr_pmp_4.cfg[0].mode  = PMP_MODE_NAPOT;
    csr_pmp_4.cfg[0].read  = 1'b0;
    csr_pmp_4.cfg[0].write = 1'b1;
    csr_pmp_4.cfg[0].exec  = 1'b0;
    csr_pmp_4.cfg[0].lock  = 1'b0;
    csr_pmp_4.addr[0]      = {20'h0, 12'hFFF, 2'b00};

    priv_lvl_4 = PRIV_LVL_M;
    pmp_req_addr_4 = 34'h0000_0100;

    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("Shared(L=0,X=0): M-mode READ allowed", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_WRITE;
    #1;
    check("Shared(L=0,X=0): M-mode WRITE allowed", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_EXEC;
    #1;
    check("Shared(L=0,X=0): M-mode EXEC denied", pmp_req_err_4, 1'b1);

    priv_lvl_4 = PRIV_LVL_U;
    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("Shared(L=0,X=0): U-mode READ allowed", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_WRITE;
    #1;
    check("Shared(L=0,X=0): U-mode WRITE denied", pmp_req_err_4, 1'b1);

    // ---- Shared: L=1, X=0 => execute only for M/S/U ----
    $display("\n--- MML=1, shared (R=0,W=1,L=1,X=0): exec only ---");
    reset_4reg();
    csr_pmp_4.mseccfg.mml = 1'b1;
    csr_pmp_4.cfg[0].mode  = PMP_MODE_NAPOT;
    csr_pmp_4.cfg[0].read  = 1'b0;
    csr_pmp_4.cfg[0].write = 1'b1;
    csr_pmp_4.cfg[0].exec  = 1'b0;
    csr_pmp_4.cfg[0].lock  = 1'b1;
    csr_pmp_4.addr[0]      = {20'h0, 12'hFFF, 2'b00};

    priv_lvl_4 = PRIV_LVL_M;
    pmp_req_addr_4 = 34'h0000_0100;

    pmp_req_type_4 = PMP_ACC_EXEC;
    #1;
    check("Shared(L=1,X=0): M-mode EXEC allowed", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("Shared(L=1,X=0): M-mode READ denied", pmp_req_err_4, 1'b1);

    priv_lvl_4 = PRIV_LVL_U;
    pmp_req_type_4 = PMP_ACC_EXEC;
    #1;
    check("Shared(L=1,X=0): U-mode EXEC allowed", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("Shared(L=1,X=0): U-mode READ denied", pmp_req_err_4, 1'b1);

    // ---- Shared: L=0, X=1 => R/W for M/S/U ----
    $display("\n--- MML=1, shared (R=0,W=1,L=0,X=1): RW all ---");
    reset_4reg();
    csr_pmp_4.mseccfg.mml = 1'b1;
    csr_pmp_4.cfg[0].mode  = PMP_MODE_NAPOT;
    csr_pmp_4.cfg[0].read  = 1'b0;
    csr_pmp_4.cfg[0].write = 1'b1;
    csr_pmp_4.cfg[0].exec  = 1'b1;
    csr_pmp_4.cfg[0].lock  = 1'b0;
    csr_pmp_4.addr[0]      = {20'h0, 12'hFFF, 2'b00};

    priv_lvl_4 = PRIV_LVL_M;
    pmp_req_addr_4 = 34'h0000_0100;

    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("Shared(L=0,X=1): M-mode READ allowed", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_WRITE;
    #1;
    check("Shared(L=0,X=1): M-mode WRITE allowed", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_EXEC;
    #1;
    check("Shared(L=0,X=1): M-mode EXEC denied", pmp_req_err_4, 1'b1);

    priv_lvl_4 = PRIV_LVL_U;
    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("Shared(L=0,X=1): U-mode READ allowed", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_WRITE;
    #1;
    check("Shared(L=0,X=1): U-mode WRITE allowed", pmp_req_err_4, 1'b0);

    // ---- Shared: L=1, X=1 => RX in M, X only in S/U ----
    $display("\n--- MML=1, shared (R=0,W=1,L=1,X=1): RX M, X S/U ---");
    reset_4reg();
    csr_pmp_4.mseccfg.mml = 1'b1;
    csr_pmp_4.cfg[0].mode  = PMP_MODE_NAPOT;
    csr_pmp_4.cfg[0].read  = 1'b0;
    csr_pmp_4.cfg[0].write = 1'b1;
    csr_pmp_4.cfg[0].exec  = 1'b1;
    csr_pmp_4.cfg[0].lock  = 1'b1;
    csr_pmp_4.addr[0]      = {20'h0, 12'hFFF, 2'b00};

    priv_lvl_4 = PRIV_LVL_M;
    pmp_req_addr_4 = 34'h0000_0100;

    pmp_req_type_4 = PMP_ACC_EXEC;
    #1;
    check("Shared(L=1,X=1): M-mode EXEC allowed", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("Shared(L=1,X=1): M-mode READ allowed", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_WRITE;
    #1;
    check("Shared(L=1,X=1): M-mode WRITE denied", pmp_req_err_4, 1'b1);

    priv_lvl_4 = PRIV_LVL_U;
    pmp_req_type_4 = PMP_ACC_EXEC;
    #1;
    check("Shared(L=1,X=1): U-mode EXEC allowed", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("Shared(L=1,X=1): U-mode READ denied", pmp_req_err_4, 1'b1);

    // ---- Shared read-only: R=1, W=1, X=1, L=1 ----
    $display("\n--- MML=1, shared read-only (R=1,W=1,X=1,L=1) ---");
    reset_4reg();
    csr_pmp_4.mseccfg.mml = 1'b1;
    csr_pmp_4.cfg[0].mode  = PMP_MODE_NAPOT;
    csr_pmp_4.cfg[0].read  = 1'b1;
    csr_pmp_4.cfg[0].write = 1'b1;
    csr_pmp_4.cfg[0].exec  = 1'b1;
    csr_pmp_4.cfg[0].lock  = 1'b1;
    csr_pmp_4.addr[0]      = {20'h0, 12'hFFF, 2'b00};

    priv_lvl_4 = PRIV_LVL_M;
    pmp_req_addr_4 = 34'h0000_0100;

    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("Shared RO (RWXL=1111): M-mode READ allowed", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_WRITE;
    #1;
    check("Shared RO (RWXL=1111): M-mode WRITE denied", pmp_req_err_4, 1'b1);

    pmp_req_type_4 = PMP_ACC_EXEC;
    #1;
    check("Shared RO (RWXL=1111): M-mode EXEC denied", pmp_req_err_4, 1'b1);

    priv_lvl_4 = PRIV_LVL_U;
    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("Shared RO (RWXL=1111): U-mode READ allowed", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_WRITE;
    #1;
    check("Shared RO (RWXL=1111): U-mode WRITE denied", pmp_req_err_4, 1'b1);

    // ---- MMWP=1 with 4 regions ----
    $display("\n--- MMWP=1, 4 regions ---");
    reset_4reg();
    csr_pmp_4.mseccfg.mmwp = 1'b1;
    csr_pmp_4.cfg[0].mode  = PMP_MODE_NAPOT;
    csr_pmp_4.cfg[0].read  = 1'b1;
    csr_pmp_4.cfg[0].write = 1'b1;
    csr_pmp_4.cfg[0].exec  = 1'b1;
    csr_pmp_4.cfg[0].lock  = 1'b0;
    csr_pmp_4.addr[0]      = {20'h0, 12'hFFF, 2'b00};

    priv_lvl_4 = PRIV_LVL_M;

    // Outside region: denied (MMWP)
    pmp_req_addr_4 = 34'h0001_0000;
    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("MMWP=1, outside region, M-mode, READ denied", pmp_req_err_4, 1'b1);

    // Inside region: allowed (matched, permissions OK)
    pmp_req_addr_4 = 34'h0000_0100;
    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("MMWP=1, inside region, M-mode, READ allowed", pmp_req_err_4, 1'b0);

    // ---- Region priority (lower number wins) ----
    $display("\n--- Region priority test ---");
    reset_4reg();
    // Region 0: TOR 0-0x2000, R only, locked
    csr_pmp_4.cfg[0].mode  = PMP_MODE_TOR;
    csr_pmp_4.cfg[0].read  = 1'b1;
    csr_pmp_4.cfg[0].write = 1'b0;
    csr_pmp_4.cfg[0].exec  = 1'b0;
    csr_pmp_4.cfg[0].lock  = 1'b1;
    csr_pmp_4.addr[0]      = 34'h0000_2000;
    // Region 1: TOR 0x2000-0x4000, W only, locked
    csr_pmp_4.cfg[1].mode  = PMP_MODE_TOR;
    csr_pmp_4.cfg[1].read  = 1'b0;
    csr_pmp_4.cfg[1].write = 1'b1;
    csr_pmp_4.cfg[1].exec  = 1'b0;
    csr_pmp_4.cfg[1].lock  = 1'b1;
    csr_pmp_4.addr[1]      = 34'h0000_4000;

    priv_lvl_4 = PRIV_LVL_M;

    pmp_req_addr_4 = 34'h0000_1000; // In region 0
    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("Priority: addr in R0, READ allowed (R=1)", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_WRITE;
    #1;
    check("Priority: addr in R0, WRITE denied (W=0, locked)", pmp_req_err_4, 1'b1);

    pmp_req_addr_4 = 34'h0000_3000; // In region 1
    pmp_req_type_4 = PMP_ACC_WRITE;
    #1;
    check("Priority: addr in R1, WRITE allowed (W=1)", pmp_req_err_4, 1'b0);

    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("Priority: addr in R1, READ denied (R=0, locked)", pmp_req_err_4, 1'b1);

    // ---- NA4 mode test ----
    $display("\n--- NA4 mode test ---");
    reset_4reg();
    csr_pmp_4.cfg[0].mode  = PMP_MODE_NA4;
    csr_pmp_4.cfg[0].read  = 1'b1;
    csr_pmp_4.cfg[0].write = 1'b1;
    csr_pmp_4.cfg[0].exec  = 1'b1;
    csr_pmp_4.cfg[0].lock  = 1'b1;
    csr_pmp_4.addr[0]      = {32'h0000_0400, 2'b00}; // 4 bytes at 0x1000

    priv_lvl_4 = PRIV_LVL_M;
    pmp_req_addr_4 = {32'h0000_0400, 2'b00}; // Matching address
    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("NA4, matching addr, M-mode, READ allowed", pmp_req_err_4, 1'b0);

    pmp_req_addr_4 = {32'h0000_0401, 2'b00}; // Different address
    #1;
    check("NA4, different addr, M-mode, READ allowed (no match, M default)", pmp_req_err_4, 1'b0);

    // U-mode at non-matching address: denied
    priv_lvl_4 = PRIV_LVL_U;
    #1;
    check("NA4, different addr, U-mode, READ denied (no match)", pmp_req_err_4, 1'b1);

    // ---- OFF mode test ----
    $display("\n--- OFF mode region test ---");
    reset_4reg();
    csr_pmp_4.cfg[0].mode  = PMP_MODE_OFF;
    csr_pmp_4.cfg[0].read  = 1'b1;
    csr_pmp_4.cfg[0].write = 1'b1;
    csr_pmp_4.cfg[0].exec  = 1'b1;
    csr_pmp_4.cfg[0].lock  = 1'b0;
    csr_pmp_4.addr[0]      = 34'h0000_2000;

    priv_lvl_4 = PRIV_LVL_U;
    pmp_req_addr_4 = 34'h0000_1000;
    pmp_req_type_4 = PMP_ACC_READ;
    #1;
    check("OFF mode, U-mode, READ denied (OFF never matches)", pmp_req_err_4, 1'b1);

    priv_lvl_4 = PRIV_LVL_M;
    #1;
    check("OFF mode, M-mode, READ allowed (M default)", pmp_req_err_4, 1'b0);

    // =========================================================================
    // Summary
    // =========================================================================
    $display("\n=== Test Summary ===");
    $display("Total: %0d  Passed: %0d  Failed: %0d", test_num, pass_count, fail_count);
    if (fail_count == 0) begin
      $display("PASS: All PMP tests passed.");
    end else begin
      $fatal(1, "FAIL: %0d test(s) failed.", fail_count);
    end
    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end

  // Timeout watchdog
  initial begin
    #100000;
    $fatal(1, "FAIL: Testbench timeout.");
    $finish;
  end

  initial begin
    $dumpfile("tb_cv32e40s_pmp_mml_patch.vcd");
    $dumpvars(0);
  end

endmodule

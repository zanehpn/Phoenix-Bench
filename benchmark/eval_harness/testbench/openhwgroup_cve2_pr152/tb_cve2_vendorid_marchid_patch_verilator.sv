module tb_cve2_vendorid_marchid_patch;

  import cve2_pkg::*;

  // ---------------------------------------------------------------
  // Expected values after the patch (OpenHW-assigned IDs)
  // MVENDORID = {MVENDORID_BANK(25'hC), MVENDORID_OFFSET(7'h2)} = 32'h0000_0602
  // MARCHID   = 32'd35 = 32'h0000_0023
  // MIMPID    = 32'h0 (unchanged)
  // MCONFIGPTR= 32'h0 (unchanged)
  // ---------------------------------------------------------------
  localparam logic [31:0] EXPECTED_MVENDORID  = 32'h0000_0602;
  localparam logic [31:0] EXPECTED_MARCHID    = 32'h0000_0023;
  localparam logic [31:0] EXPECTED_MIMPID     = 32'h0000_0000;
  localparam logic [31:0] EXPECTED_MCONFIGPTR = 32'h0000_0000;
  localparam int PMP_REGIONS = 4;

  // Pre-patch (old Ibex) values -- used to verify the patch changed something
  localparam logic [31:0] OLD_MVENDORID = 32'h0000_0000;
  localparam logic [31:0] OLD_MARCHID   = {1'b0, 31'd22};  // 32'h0000_0016

  logic clk = 1'b0;
  logic rst_ni = 1'b0;

  // CSR interface
  logic                 csr_access_i;
  csr_num_e             csr_addr_i;
  logic [31:0]          csr_wdata_i;
  csr_op_e              csr_op_i;
  logic                 csr_op_en_i;
  logic [31:0]          csr_rdata_o;

  // Misc inputs
  logic [31:0]          hart_id_i;
  logic                 csr_mtvec_init_i;
  logic [31:0]          boot_addr_i;
  logic                 irq_software_i, irq_timer_i, irq_external_i;
  logic [15:0]          irq_fast_i;
  logic                 nmi_mode_i;
  logic                 debug_mode_i;
  dbg_cause_e           debug_cause_i;
  logic                 debug_csr_save_i;
  logic [31:0]          pc_if_i, pc_id_i;
  logic                 csr_save_if_i, csr_save_id_i;
  logic                 csr_restore_mret_i, csr_restore_dret_i;
  logic                 csr_save_cause_i;
  exc_cause_e           csr_mcause_i;
  logic [31:0]          csr_mtval_i;
  logic                 instr_ret_i, instr_ret_compressed_i;
  logic                 iside_wait_i, jump_i, branch_i, branch_taken_i;
  logic                 mem_load_i, mem_store_i;
  logic                 dside_wait_i, wfi_wait_i, div_wait_i;

  // Unused outputs
  priv_lvl_e            priv_mode_id_o, priv_mode_lsu_o;
  logic                 csr_mstatus_tw_o;
  logic [31:0]          csr_mtvec_o;
  logic                 irq_pending_o;
  irqs_t                irqs_o;
  logic                 csr_mstatus_mie_o;
  logic [31:0]          csr_mepc_o;
  pmp_cfg_t             csr_pmp_cfg_o   [PMP_REGIONS];
  logic [33:0]          csr_pmp_addr_o  [PMP_REGIONS];
  pmp_mseccfg_t         csr_pmp_mseccfg_o;
  logic [31:0]          csr_depc_o;
  logic                 debug_single_step_o;
  logic                 debug_ebreakm_o, debug_ebreaku_o;
  logic                 trigger_match_o;
  logic                 illegal_csr_insn_o;

  // Scoreboard
  int pass_count = 0;
  int fail_count = 0;
  int test_num   = 0;

  always #5 clk = ~clk;

  cve2_cs_registers #(
    .PMPNumRegions(PMP_REGIONS)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_ni),
    .hart_id_i(hart_id_i),
    .priv_mode_id_o(priv_mode_id_o),
    .priv_mode_lsu_o(priv_mode_lsu_o),
    .csr_mstatus_tw_o(csr_mstatus_tw_o),
    .csr_mtvec_o(csr_mtvec_o),
    .csr_mtvec_init_i(csr_mtvec_init_i),
    .boot_addr_i(boot_addr_i),
    .csr_access_i(csr_access_i),
    .csr_addr_i(csr_addr_i),
    .csr_wdata_i(csr_wdata_i),
    .csr_op_i(csr_op_i),
    .csr_op_en_i(csr_op_en_i),
    .csr_rdata_o(csr_rdata_o),
    .irq_software_i(irq_software_i),
    .irq_timer_i(irq_timer_i),
    .irq_external_i(irq_external_i),
    .irq_fast_i(irq_fast_i),
    .nmi_mode_i(nmi_mode_i),
    .irq_pending_o(irq_pending_o),
    .irqs_o(irqs_o),
    .csr_mstatus_mie_o(csr_mstatus_mie_o),
    .csr_mepc_o(csr_mepc_o),
    .csr_pmp_cfg_o(csr_pmp_cfg_o),
    .csr_pmp_addr_o(csr_pmp_addr_o),
    .csr_pmp_mseccfg_o(csr_pmp_mseccfg_o),
    .debug_mode_i(debug_mode_i),
    .debug_cause_i(debug_cause_i),
    .debug_csr_save_i(debug_csr_save_i),
    .csr_depc_o(csr_depc_o),
    .debug_single_step_o(debug_single_step_o),
    .debug_ebreakm_o(debug_ebreakm_o),
    .debug_ebreaku_o(debug_ebreaku_o),
    .trigger_match_o(trigger_match_o),
    .pc_if_i(pc_if_i),
    .pc_id_i(pc_id_i),
    .csr_save_if_i(csr_save_if_i),
    .csr_save_id_i(csr_save_id_i),
    .csr_restore_mret_i(csr_restore_mret_i),
    .csr_restore_dret_i(csr_restore_dret_i),
    .csr_save_cause_i(csr_save_cause_i),
    .csr_mcause_i(csr_mcause_i),
    .csr_mtval_i(csr_mtval_i),
    .illegal_csr_insn_o(illegal_csr_insn_o),
    .instr_ret_i(instr_ret_i),
    .instr_ret_compressed_i(instr_ret_compressed_i),
    .iside_wait_i(iside_wait_i),
    .jump_i(jump_i),
    .branch_i(branch_i),
    .branch_taken_i(branch_taken_i),
    .mem_load_i(mem_load_i),
    .mem_store_i(mem_store_i),
    .dside_wait_i(dside_wait_i),
    .wfi_wait_i(wfi_wait_i),
    .div_wait_i(div_wait_i)
  );

  // -----------------------------------------------------------------
  // Helper tasks
  // -----------------------------------------------------------------
  task automatic drive_idle_inputs;
    hart_id_i               = '0;
    csr_access_i            = 1'b0;
    csr_addr_i              = CSR_MVENDORID;
    csr_wdata_i             = '0;
    csr_op_i                = CSR_OP_READ;
    csr_op_en_i             = 1'b0;
    csr_mtvec_init_i        = 1'b0;
    boot_addr_i             = '0;
    irq_software_i          = 1'b0;
    irq_timer_i             = 1'b0;
    irq_external_i          = 1'b0;
    irq_fast_i              = '0;
    nmi_mode_i              = 1'b0;
    debug_mode_i            = 1'b0;
    debug_cause_i           = DBG_CAUSE_NONE;
    debug_csr_save_i        = 1'b0;
    pc_if_i                 = '0;
    pc_id_i                 = '0;
    csr_save_if_i           = 1'b0;
    csr_save_id_i           = 1'b0;
    csr_restore_mret_i      = 1'b0;
    csr_restore_dret_i      = 1'b0;
    csr_save_cause_i        = 1'b0;
    csr_mcause_i            = EXC_CAUSE_INSTR_ACCESS_FAULT;
    csr_mtval_i             = '0;
    instr_ret_i             = 1'b0;
    instr_ret_compressed_i  = 1'b0;
    iside_wait_i            = 1'b0;
    jump_i                  = 1'b0;
    branch_i                = 1'b0;
    branch_taken_i          = 1'b0;
    mem_load_i              = 1'b0;
    mem_store_i             = 1'b0;
    dside_wait_i            = 1'b0;
    wfi_wait_i              = 1'b0;
    div_wait_i              = 1'b0;
  endtask

  // Read a CSR and return data + illegal flag
  task automatic csr_read(input csr_num_e addr,
                          output logic [31:0] data,
                          output logic        illegal);
    @(posedge clk);
    csr_addr_i   = addr;
    csr_access_i = 1'b1;
    csr_op_en_i  = 1'b1;
    csr_op_i     = CSR_OP_READ;
    csr_wdata_i  = '0;
    @(posedge clk);
    data    = csr_rdata_o;
    illegal = illegal_csr_insn_o;
    csr_access_i = 1'b0;
    csr_op_en_i  = 1'b0;
  endtask

  // Write a CSR using the given operation and return read-back data + illegal flag
  task automatic csr_write(input csr_num_e  addr,
                           input csr_op_e   op,
                           input logic [31:0] wdata,
                           output logic        illegal);
    @(posedge clk);
    csr_addr_i   = addr;
    csr_access_i = 1'b1;
    csr_op_en_i  = 1'b1;
    csr_op_i     = op;
    csr_wdata_i  = wdata;
    @(posedge clk);
    illegal = illegal_csr_insn_o;
    csr_access_i = 1'b0;
    csr_op_en_i  = 1'b0;
  endtask

  // Check helper: compare observed vs expected
  task automatic check(input string tag,
                       input logic [31:0] observed,
                       input logic [31:0] expected);
    test_num++;
    if (observed !== expected) begin
      $fatal(1, "FAIL [%0d] %s: got 0x%08x, expected 0x%08x", test_num, tag, observed, expected);
      fail_count++;
    end else begin
      $display("  OK [%0d] %s: 0x%08x", test_num, tag, observed);
      pass_count++;
    end
  endtask

  // Check a boolean condition
  task automatic check_bool(input string tag,
                            input logic  condition,
                            input logic  expected);
    test_num++;
    if (condition !== expected) begin
      $fatal(1, "FAIL [%0d] %s: got %0b, expected %0b", test_num, tag, condition, expected);
      fail_count++;
    end else begin
      $display("  OK [%0d] %s: %0b", test_num, tag, condition);
      pass_count++;
    end
  endtask

  // -----------------------------------------------------------------
  // Main stimulus
  // -----------------------------------------------------------------
  initial begin
    logic [31:0] rd;
    logic        ill;

    drive_idle_inputs();

    // Hold reset for several cycles
    repeat (5) @(posedge clk);
    rst_ni = 1'b1;
    repeat (5) @(posedge clk);

    // =============================================================
    // TEST GROUP 1: Basic read-back of patched ID CSRs
    // =============================================================
    $display("\n--- Test Group 1: Basic read-back of patched ID CSRs ---");

    csr_read(CSR_MVENDORID, rd, ill);
    check("MVENDORID value", rd, EXPECTED_MVENDORID);
    check_bool("MVENDORID not illegal", ill, 1'b0);

    csr_read(CSR_MARCHID, rd, ill);
    check("MARCHID value", rd, EXPECTED_MARCHID);
    check_bool("MARCHID not illegal", ill, 1'b0);

    csr_read(CSR_MIMPID, rd, ill);
    check("MIMPID value", rd, EXPECTED_MIMPID);
    check_bool("MIMPID not illegal", ill, 1'b0);

    csr_read(CSR_MCONFIGPTR, rd, ill);
    check("MCONFIGPTR value", rd, EXPECTED_MCONFIGPTR);
    check_bool("MCONFIGPTR not illegal", ill, 1'b0);

    // =============================================================
    // TEST GROUP 2: Verify the patch changed the old values
    //   MVENDORID was 0x0, now must be 0x602
    //   MARCHID   was 0x16, now must be 0x23
    // =============================================================
    $display("\n--- Test Group 2: Old values must NOT match (patch applied) ---");

    csr_read(CSR_MVENDORID, rd, ill);
    test_num++;
    if (rd === OLD_MVENDORID) begin
      $fatal(1, "FAIL [%0d] MVENDORID still matches old Ibex value 0x%08x", test_num, OLD_MVENDORID);
      fail_count++;
    end else begin
      $display("  OK [%0d] MVENDORID differs from old Ibex value", test_num);
      pass_count++;
    end

    csr_read(CSR_MARCHID, rd, ill);
    test_num++;
    if (rd === OLD_MARCHID) begin
      $fatal(1, "FAIL [%0d] MARCHID still matches old Ibex value 0x%08x", test_num, OLD_MARCHID);
      fail_count++;
    end else begin
      $display("  OK [%0d] MARCHID differs from old Ibex value", test_num);
      pass_count++;
    end

    // =============================================================
    // TEST GROUP 3: Bit-field encoding checks for MVENDORID
    //   [6:0]  = MVENDORID_OFFSET = 7'h02
    //   [31:7] = MVENDORID_BANK   = 25'hC (decimal 12)
    // =============================================================
    $display("\n--- Test Group 3: MVENDORID bit-field encoding ---");

    csr_read(CSR_MVENDORID, rd, ill);
    check("MVENDORID offset [6:0]", {25'b0, rd[6:0]}, {25'b0, 7'h02});
    check("MVENDORID bank [31:7]", {rd[31:7], 7'b0}, {25'hC, 7'b0});

    // =============================================================
    // TEST GROUP 4: MARCHID top-bit must be 0 (open-source project)
    // =============================================================
    $display("\n--- Test Group 4: MARCHID open-source bit ---");

    csr_read(CSR_MARCHID, rd, ill);
    check_bool("MARCHID[31] == 0 (open-source)", rd[31], 1'b0);
    check("MARCHID lower 31 bits = 35", {1'b0, rd[30:0]}, 32'd35);

    // =============================================================
    // TEST GROUP 5: Read-only property -- writes must NOT change value
    //   CSR addresses 0xF1x have top 2 bits = 2'b11, which means
    //   read-only. A CSR_OP_WRITE should be flagged illegal.
    // =============================================================
    $display("\n--- Test Group 5: Read-only CSR write attempts ---");

    // Attempt CSR_OP_WRITE to MVENDORID
    csr_write(CSR_MVENDORID, CSR_OP_WRITE, 32'hDEAD_BEEF, ill);
    check_bool("MVENDORID write flagged illegal", ill, 1'b1);
    // Read back and verify value unchanged
    csr_read(CSR_MVENDORID, rd, ill);
    check("MVENDORID unchanged after write attempt", rd, EXPECTED_MVENDORID);

    // Attempt CSR_OP_SET to MARCHID
    csr_write(CSR_MARCHID, CSR_OP_SET, 32'hFFFF_FFFF, ill);
    check_bool("MARCHID set flagged illegal", ill, 1'b1);
    csr_read(CSR_MARCHID, rd, ill);
    check("MARCHID unchanged after set attempt", rd, EXPECTED_MARCHID);

    // Attempt CSR_OP_CLEAR to MIMPID
    csr_write(CSR_MIMPID, CSR_OP_CLEAR, 32'hFFFF_FFFF, ill);
    check_bool("MIMPID clear flagged illegal", ill, 1'b1);
    csr_read(CSR_MIMPID, rd, ill);
    check("MIMPID unchanged after clear attempt", rd, EXPECTED_MIMPID);

    // Attempt CSR_OP_WRITE to MCONFIGPTR
    csr_write(CSR_MCONFIGPTR, CSR_OP_WRITE, 32'hCAFE_BABE, ill);
    check_bool("MCONFIGPTR write flagged illegal", ill, 1'b1);
    csr_read(CSR_MCONFIGPTR, rd, ill);
    check("MCONFIGPTR unchanged after write attempt", rd, EXPECTED_MCONFIGPTR);

    // =============================================================
    // TEST GROUP 6: MHARTID reflects hart_id_i input
    // =============================================================
    $display("\n--- Test Group 6: MHARTID reflects hart_id_i ---");

    hart_id_i = 32'h0000_0000;
    csr_read(CSR_MHARTID, rd, ill);
    check("MHARTID with hart_id=0", rd, 32'h0000_0000);
    check_bool("MHARTID not illegal", ill, 1'b0);

    hart_id_i = 32'h0000_0001;
    csr_read(CSR_MHARTID, rd, ill);
    check("MHARTID with hart_id=1", rd, 32'h0000_0001);

    hart_id_i = 32'hFFFF_FFFF;
    csr_read(CSR_MHARTID, rd, ill);
    check("MHARTID with hart_id=0xFFFFFFFF", rd, 32'hFFFF_FFFF);

    hart_id_i = 32'hA5A5_5A5A;
    csr_read(CSR_MHARTID, rd, ill);
    check("MHARTID with hart_id=0xA5A55A5A", rd, 32'hA5A5_5A5A);

    // Write attempt to MHARTID (read-only)
    csr_write(CSR_MHARTID, CSR_OP_WRITE, 32'h0000_0042, ill);
    check_bool("MHARTID write flagged illegal", ill, 1'b1);

    hart_id_i = 32'h0000_0000;  // restore

    // =============================================================
    // TEST GROUP 7: Repeated reads return stable values
    // =============================================================
    $display("\n--- Test Group 7: Repeated reads return stable values ---");

    begin
      logic [31:0] rd1, rd2, rd3;
      csr_read(CSR_MVENDORID, rd1, ill);
      csr_read(CSR_MVENDORID, rd2, ill);
      csr_read(CSR_MVENDORID, rd3, ill);
      check("MVENDORID read consistency (1==2)", rd1, rd2);
      check("MVENDORID read consistency (2==3)", rd2, rd3);

      csr_read(CSR_MARCHID, rd1, ill);
      csr_read(CSR_MARCHID, rd2, ill);
      csr_read(CSR_MARCHID, rd3, ill);
      check("MARCHID read consistency (1==2)", rd1, rd2);
      check("MARCHID read consistency (2==3)", rd2, rd3);
    end

    // =============================================================
    // TEST GROUP 8: Values stable across reset
    // =============================================================
    $display("\n--- Test Group 8: Values stable across reset ---");

    // Assert reset
    rst_ni = 1'b0;
    repeat (3) @(posedge clk);
    rst_ni = 1'b1;
    repeat (3) @(posedge clk);

    csr_read(CSR_MVENDORID, rd, ill);
    check("MVENDORID after reset", rd, EXPECTED_MVENDORID);

    csr_read(CSR_MARCHID, rd, ill);
    check("MARCHID after reset", rd, EXPECTED_MARCHID);

    csr_read(CSR_MIMPID, rd, ill);
    check("MIMPID after reset", rd, EXPECTED_MIMPID);

    csr_read(CSR_MCONFIGPTR, rd, ill);
    check("MCONFIGPTR after reset", rd, EXPECTED_MCONFIGPTR);

    // =============================================================
    // TEST GROUP 9: Other read-only CSRs unaffected (MISA sanity)
    // =============================================================
    $display("\n--- Test Group 9: MISA sanity check ---");

    csr_read(CSR_MISA, rd, ill);
    check_bool("MISA not illegal", ill, 1'b0);
    // MXL field [31:30] should be 2'd1 for RV32
    check("MISA MXL field", {30'b0, rd[31:30]}, {30'b0, 2'd1});
    // I bit [8] should be set (RV32I)
    check_bool("MISA I-extension bit", rd[8], 1'b1);
    // C bit [2] should be set (compressed)
    check_bool("MISA C-extension bit", rd[2], 1'b1);

    // =============================================================
    // TEST GROUP 10: Read-write CSR (MSCRATCH) still works
    //   Ensures read-only enforcement is specific to RO registers
    // =============================================================
    $display("\n--- Test Group 10: Read-write CSR (MSCRATCH) still works ---");

    csr_write(CSR_MSCRATCH, CSR_OP_WRITE, 32'h1234_5678, ill);
    check_bool("MSCRATCH write not illegal", ill, 1'b0);
    csr_read(CSR_MSCRATCH, rd, ill);
    check("MSCRATCH readback after write", rd, 32'h1234_5678);

    // CSR_OP_SET
    csr_write(CSR_MSCRATCH, CSR_OP_SET, 32'h0000_000F, ill);
    csr_read(CSR_MSCRATCH, rd, ill);
    check("MSCRATCH after set 0xF", rd, 32'h1234_567F);

    // CSR_OP_CLEAR
    csr_write(CSR_MSCRATCH, CSR_OP_CLEAR, 32'h0000_00FF, ill);
    csr_read(CSR_MSCRATCH, rd, ill);
    check("MSCRATCH after clear 0xFF", rd, 32'h1234_5600);

    // =============================================================
    // TEST GROUP 11: ID CSRs stable while other CSR traffic occurs
    // =============================================================
    $display("\n--- Test Group 11: ID CSRs stable during other CSR traffic ---");

    // Write MSCRATCH with different patterns, interleave ID reads
    csr_write(CSR_MSCRATCH, CSR_OP_WRITE, 32'hAAAA_AAAA, ill);
    csr_read(CSR_MVENDORID, rd, ill);
    check("MVENDORID stable during MSCRATCH traffic", rd, EXPECTED_MVENDORID);

    csr_write(CSR_MSCRATCH, CSR_OP_WRITE, 32'h5555_5555, ill);
    csr_read(CSR_MARCHID, rd, ill);
    check("MARCHID stable during MSCRATCH traffic", rd, EXPECTED_MARCHID);

    csr_write(CSR_MSCRATCH, CSR_OP_WRITE, 32'hFFFF_FFFF, ill);
    csr_read(CSR_MIMPID, rd, ill);
    check("MIMPID stable during MSCRATCH traffic", rd, EXPECTED_MIMPID);

    // =============================================================
    // TEST GROUP 12: Back-to-back reads of different ID CSRs
    // =============================================================
    $display("\n--- Test Group 12: Back-to-back reads of different ID CSRs ---");

    csr_read(CSR_MVENDORID, rd, ill);
    check("B2B MVENDORID", rd, EXPECTED_MVENDORID);
    csr_read(CSR_MARCHID, rd, ill);
    check("B2B MARCHID", rd, EXPECTED_MARCHID);
    csr_read(CSR_MIMPID, rd, ill);
    check("B2B MIMPID", rd, EXPECTED_MIMPID);
    csr_read(CSR_MHARTID, rd, ill);
    check("B2B MHARTID", rd, 32'h0);
    csr_read(CSR_MCONFIGPTR, rd, ill);
    check("B2B MCONFIGPTR", rd, EXPECTED_MCONFIGPTR);

    // Reverse order
    csr_read(CSR_MCONFIGPTR, rd, ill);
    check("B2B rev MCONFIGPTR", rd, EXPECTED_MCONFIGPTR);
    csr_read(CSR_MHARTID, rd, ill);
    check("B2B rev MHARTID", rd, 32'h0);
    csr_read(CSR_MIMPID, rd, ill);
    check("B2B rev MIMPID", rd, EXPECTED_MIMPID);
    csr_read(CSR_MARCHID, rd, ill);
    check("B2B rev MARCHID", rd, EXPECTED_MARCHID);
    csr_read(CSR_MVENDORID, rd, ill);
    check("B2B rev MVENDORID", rd, EXPECTED_MVENDORID);

    // =============================================================
    // TEST GROUP 13: Multiple write attempts with different ops
    //   to the same read-only CSR, value must never change
    // =============================================================
    $display("\n--- Test Group 13: Exhaustive write-attempt patterns to MVENDORID ---");

    csr_write(CSR_MVENDORID, CSR_OP_WRITE, 32'h0000_0000, ill);
    csr_read(CSR_MVENDORID, rd, ill);
    check("MVENDORID after write 0x0", rd, EXPECTED_MVENDORID);

    csr_write(CSR_MVENDORID, CSR_OP_WRITE, 32'hFFFF_FFFF, ill);
    csr_read(CSR_MVENDORID, rd, ill);
    check("MVENDORID after write 0xFFFFFFFF", rd, EXPECTED_MVENDORID);

    csr_write(CSR_MVENDORID, CSR_OP_SET, 32'hFFFF_FFFF, ill);
    csr_read(CSR_MVENDORID, rd, ill);
    check("MVENDORID after set 0xFFFFFFFF", rd, EXPECTED_MVENDORID);

    csr_write(CSR_MVENDORID, CSR_OP_CLEAR, 32'hFFFF_FFFF, ill);
    csr_read(CSR_MVENDORID, rd, ill);
    check("MVENDORID after clear 0xFFFFFFFF", rd, EXPECTED_MVENDORID);

    // =============================================================
    // TEST GROUP 14: Exhaustive write ops to all RO ID CSRs
    // =============================================================
    $display("\n--- Test Group 14: All write ops to all RO ID CSRs ---");

    // MARCHID: WRITE, CLEAR (SET already done in group 5)
    csr_write(CSR_MARCHID, CSR_OP_WRITE, 32'hFFFF_FFFF, ill);
    check_bool("MARCHID write flagged illegal", ill, 1'b1);
    csr_read(CSR_MARCHID, rd, ill);
    check("MARCHID unchanged after write", rd, EXPECTED_MARCHID);

    csr_write(CSR_MARCHID, CSR_OP_CLEAR, 32'hFFFF_FFFF, ill);
    check_bool("MARCHID clear flagged illegal", ill, 1'b1);
    csr_read(CSR_MARCHID, rd, ill);
    check("MARCHID unchanged after clear", rd, EXPECTED_MARCHID);

    // MIMPID: WRITE, SET (CLEAR already done in group 5)
    csr_write(CSR_MIMPID, CSR_OP_WRITE, 32'hFFFF_FFFF, ill);
    check_bool("MIMPID write flagged illegal", ill, 1'b1);
    csr_read(CSR_MIMPID, rd, ill);
    check("MIMPID unchanged after write", rd, EXPECTED_MIMPID);

    csr_write(CSR_MIMPID, CSR_OP_SET, 32'hFFFF_FFFF, ill);
    check_bool("MIMPID set flagged illegal", ill, 1'b1);
    csr_read(CSR_MIMPID, rd, ill);
    check("MIMPID unchanged after set", rd, EXPECTED_MIMPID);

    // MCONFIGPTR: SET, CLEAR (WRITE already done in group 5)
    csr_write(CSR_MCONFIGPTR, CSR_OP_SET, 32'hFFFF_FFFF, ill);
    check_bool("MCONFIGPTR set flagged illegal", ill, 1'b1);
    csr_read(CSR_MCONFIGPTR, rd, ill);
    check("MCONFIGPTR unchanged after set", rd, EXPECTED_MCONFIGPTR);

    csr_write(CSR_MCONFIGPTR, CSR_OP_CLEAR, 32'hFFFF_FFFF, ill);
    check_bool("MCONFIGPTR clear flagged illegal", ill, 1'b1);
    csr_read(CSR_MCONFIGPTR, rd, ill);
    check("MCONFIGPTR unchanged after clear", rd, EXPECTED_MCONFIGPTR);

    // MHARTID: SET, CLEAR (WRITE already done in group 6)
    csr_write(CSR_MHARTID, CSR_OP_SET, 32'hFFFF_FFFF, ill);
    check_bool("MHARTID set flagged illegal", ill, 1'b1);

    csr_write(CSR_MHARTID, CSR_OP_CLEAR, 32'hFFFF_FFFF, ill);
    check_bool("MHARTID clear flagged illegal", ill, 1'b1);

    // =============================================================
    // Summary
    // =============================================================
    $display("\n========================================");
    $display("Test complete: %0d passed, %0d failed out of %0d", pass_count, fail_count, test_num);
    $display("========================================");

    if (fail_count == 0) begin
      $display("PASS: All CSR mvendorid/marchid/mimpid/mconfigptr tests passed.");
    end else begin
      $fatal(1, "FAIL: %0d test(s) failed.", fail_count);
    end

    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end

  // ---------------------------------------------------------------
  // Patch-focused functional coverage
  // ---------------------------------------------------------------
  // [verilator-strip cg] covergroup cg_patch;
// [verilator-strip cg]     // Coverpoint: CSR address being read
// [verilator-strip cg]     cp_csr_addr: coverpoint csr_addr_i {
// [verilator-strip cg]       bins mvendorid  = {CSR_MVENDORID};
// [verilator-strip cg]       bins marchid    = {CSR_MARCHID};
// [verilator-strip cg]       bins mimpid     = {CSR_MIMPID};
// [verilator-strip cg]       bins mconfigptr = {CSR_MCONFIGPTR};
// [verilator-strip cg]       bins mhartid    = {CSR_MHARTID};
// [verilator-strip cg]       // Other CSR addresses are not relevant to this patch's coverage
// [verilator-strip cg]     }
// [verilator-strip cg]     // Coverpoint: CSR operation type
// [verilator-strip cg]     cp_csr_op: coverpoint csr_op_i {
// [verilator-strip cg]       bins op_read  = {CSR_OP_READ};
// [verilator-strip cg]       bins op_write = {CSR_OP_WRITE};
// [verilator-strip cg]       bins op_set   = {CSR_OP_SET};
// [verilator-strip cg]       bins op_clear = {CSR_OP_CLEAR};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cross: CSR address with operation type
// [verilator-strip cg]     cx_addr_op: cross cp_csr_addr, cp_csr_op;
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_patch cg_inst = new();

  always @(posedge clk) begin
    if (rst_ni && csr_access_i)
      /* [verilator-strip sample] */;
  end

  // Timeout watchdog
  initial begin
    #100_000;
    $fatal(1, "FAIL: Simulation timeout.");
    $finish;
  end

  initial begin
    $dumpfile("tb_cve2_vendorid_marchid_patch.vcd");
    $dumpvars(0);
  end

endmodule

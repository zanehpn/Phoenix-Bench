module tb_cve2_dret_minstret_patch;

  import cve2_pkg::*;

  localparam logic [31:0] DRET_INSN = 32'h7B20_0073;

  logic clk = 1'b0;
  logic rst_ni = 1'b0;

  // Inputs to ID stage
  logic                  fetch_enable_i;
  logic                  instr_valid_i;
  logic [31:0]           instr_rdata_i;
  logic [31:0]           instr_rdata_alu_i;
  logic [15:0]           instr_rdata_c_i;
  logic                  instr_is_compressed_i;
  logic                  branch_decision_i;
  logic                  illegal_c_insn_i;
  logic                  instr_fetch_err_i;
  logic                  instr_fetch_err_plus2_i;
  logic [31:0]           pc_id_i;
  logic                  ex_valid_i;
  logic                  lsu_resp_valid_i;
  logic [1:0]            imd_val_we_ex_i;
  logic [33:0]           imd_val_d_ex_i [2];
  logic                  lsu_addr_incr_req_i;
  logic [31:0]           lsu_addr_last_i;
  logic                  csr_mstatus_mie_i;
  logic                  irq_pending_i;
  irqs_t                 irqs_i;
  logic                  irq_nm_i;
  logic                  lsu_load_err_i;
  logic                  lsu_store_err_i;
  priv_lvl_e             priv_mode_i;
  logic                  csr_mstatus_tw_i;
  logic                  illegal_csr_insn_i;
  logic                  debug_req_i;
  logic                  debug_single_step_i;
  logic                  debug_ebreakm_i;
  logic                  debug_ebreaku_i;
  logic                  trigger_match_i;
  logic [31:0]           result_ex_i;
  logic [31:0]           csr_rdata_i;
  logic [31:0]           rf_rdata_a_i;
  logic [31:0]           rf_rdata_b_i;

  // Outputs that we observe or tie off
  logic                  ctrl_busy_o;
  logic                  illegal_insn_o;
  logic                  instr_req_o;
  logic                  instr_first_cycle_id_o;
  logic                  instr_valid_clear_o;
  logic                  id_in_ready_o;
  logic                  pc_set_o;
  pc_sel_e               pc_mux_o;
  exc_pc_sel_e           exc_pc_mux_o;
  exc_cause_e            exc_cause_o;
  alu_op_e               alu_operator_ex_o;
  logic [31:0]           alu_operand_a_ex_o;
  logic [31:0]           alu_operand_b_ex_o;
  logic [33:0]           imd_val_q_ex_o [2];
  logic                  mult_en_ex_o;
  logic                  div_en_ex_o;
  logic                  mult_sel_ex_o;
  logic                  div_sel_ex_o;
  md_op_e                multdiv_operator_ex_o;
  logic [1:0]            multdiv_signed_mode_ex_o;
  logic [31:0]           multdiv_operand_a_ex_o;
  logic [31:0]           multdiv_operand_b_ex_o;
  logic                  csr_access_o;
  csr_op_e               csr_op_o;
  logic                  csr_op_en_o;
  logic                  csr_save_if_o;
  logic                  csr_save_id_o;
  logic                  csr_restore_mret_id_o;
  logic                  csr_restore_dret_id_o;
  logic                  csr_save_cause_o;
  logic [31:0]           csr_mtval_o;
  logic                  lsu_req_o;
  logic                  lsu_we_o;
  logic [1:0]            lsu_type_o;
  logic                  lsu_sign_ext_o;
  logic [31:0]           lsu_wdata_o;
  logic                  nmi_mode_o;
  logic                  debug_mode_o;
  dbg_cause_e            debug_cause_o;
  logic                  debug_csr_save_o;
  logic [4:0]            rf_raddr_a_o;
  logic [4:0]            rf_raddr_b_o;
  logic                  rf_ren_a_o;
  logic                  rf_ren_b_o;
  logic [4:0]            rf_waddr_id_o;
  logic [31:0]           rf_wdata_id_o;
  logic                  rf_we_id_o;
  logic                  en_wb_o;
  logic                  instr_perf_count_id_o;
  logic                  perf_jump_o;
  logic                  perf_branch_o;
  logic                  perf_tbranch_o;
  logic                  perf_dside_wait_o;
  logic                  perf_wfi_wait_o;
  logic                  perf_div_wait_o;
  logic                  instr_id_done_o;

  always #5 clk = ~clk;

  cve2_id_stage dut (
    .clk_i(clk),
    .rst_ni(rst_ni),
    .fetch_enable_i(fetch_enable_i),
    .ctrl_busy_o(ctrl_busy_o),
    .illegal_insn_o(illegal_insn_o),
    .instr_valid_i(instr_valid_i),
    .instr_rdata_i(instr_rdata_i),
    .instr_rdata_alu_i(instr_rdata_alu_i),
    .instr_rdata_c_i(instr_rdata_c_i),
    .instr_is_compressed_i(instr_is_compressed_i),
    .instr_req_o(instr_req_o),
    .instr_first_cycle_id_o(instr_first_cycle_id_o),
    .instr_valid_clear_o(instr_valid_clear_o),
    .id_in_ready_o(id_in_ready_o),
    .branch_decision_i(branch_decision_i),
    .pc_set_o(pc_set_o),
    .pc_mux_o(pc_mux_o),
    .exc_pc_mux_o(exc_pc_mux_o),
    .exc_cause_o(exc_cause_o),
    .illegal_c_insn_i(illegal_c_insn_i),
    .instr_fetch_err_i(instr_fetch_err_i),
    .instr_fetch_err_plus2_i(instr_fetch_err_plus2_i),
    .pc_id_i(pc_id_i),
    .ex_valid_i(ex_valid_i),
    .lsu_resp_valid_i(lsu_resp_valid_i),
    .alu_operator_ex_o(alu_operator_ex_o),
    .alu_operand_a_ex_o(alu_operand_a_ex_o),
    .alu_operand_b_ex_o(alu_operand_b_ex_o),
    .imd_val_we_ex_i(imd_val_we_ex_i),
    .imd_val_d_ex_i(imd_val_d_ex_i),
    .imd_val_q_ex_o(imd_val_q_ex_o),
    .mult_en_ex_o(mult_en_ex_o),
    .div_en_ex_o(div_en_ex_o),
    .mult_sel_ex_o(mult_sel_ex_o),
    .div_sel_ex_o(div_sel_ex_o),
    .multdiv_operator_ex_o(multdiv_operator_ex_o),
    .multdiv_signed_mode_ex_o(multdiv_signed_mode_ex_o),
    .multdiv_operand_a_ex_o(multdiv_operand_a_ex_o),
    .multdiv_operand_b_ex_o(multdiv_operand_b_ex_o),
    .csr_access_o(csr_access_o),
    .csr_op_o(csr_op_o),
    .csr_op_en_o(csr_op_en_o),
    .csr_save_if_o(csr_save_if_o),
    .csr_save_id_o(csr_save_id_o),
    .csr_restore_mret_id_o(csr_restore_mret_id_o),
    .csr_restore_dret_id_o(csr_restore_dret_id_o),
    .csr_save_cause_o(csr_save_cause_o),
    .csr_mtval_o(csr_mtval_o),
    .priv_mode_i(priv_mode_i),
    .csr_mstatus_tw_i(csr_mstatus_tw_i),
    .illegal_csr_insn_i(illegal_csr_insn_i),
    .lsu_req_o(lsu_req_o),
    .lsu_we_o(lsu_we_o),
    .lsu_type_o(lsu_type_o),
    .lsu_sign_ext_o(lsu_sign_ext_o),
    .lsu_wdata_o(lsu_wdata_o),
    .lsu_addr_incr_req_i(lsu_addr_incr_req_i),
    .lsu_addr_last_i(lsu_addr_last_i),
    .csr_mstatus_mie_i(csr_mstatus_mie_i),
    .irq_pending_i(irq_pending_i),
    .irqs_i(irqs_i),
    .irq_nm_i(irq_nm_i),
    .nmi_mode_o(nmi_mode_o),
    .lsu_load_err_i(lsu_load_err_i),
    .lsu_store_err_i(lsu_store_err_i),
    .debug_mode_o(debug_mode_o),
    .debug_cause_o(debug_cause_o),
    .debug_csr_save_o(debug_csr_save_o),
    .debug_req_i(debug_req_i),
    .debug_single_step_i(debug_single_step_i),
    .debug_ebreakm_i(debug_ebreakm_i),
    .debug_ebreaku_i(debug_ebreaku_i),
    .trigger_match_i(trigger_match_i),
    .result_ex_i(result_ex_i),
    .csr_rdata_i(csr_rdata_i),
    .rf_raddr_a_o(rf_raddr_a_o),
    .rf_rdata_a_i(rf_rdata_a_i),
    .rf_raddr_b_o(rf_raddr_b_o),
    .rf_rdata_b_i(rf_rdata_b_i),
    .rf_ren_a_o(rf_ren_a_o),
    .rf_ren_b_o(rf_ren_b_o),
    .rf_waddr_id_o(rf_waddr_id_o),
    .rf_wdata_id_o(rf_wdata_id_o),
    .rf_we_id_o(rf_we_id_o),
    .en_wb_o(en_wb_o),
    .instr_perf_count_id_o(instr_perf_count_id_o),
    .perf_jump_o(perf_jump_o),
    .perf_branch_o(perf_branch_o),
    .perf_tbranch_o(perf_tbranch_o),
    .perf_dside_wait_o(perf_dside_wait_o),
    .perf_wfi_wait_o(perf_wfi_wait_o),
    .perf_div_wait_o(perf_div_wait_o),
    .instr_id_done_o(instr_id_done_o)
  );

  task automatic drive_defaults;
    fetch_enable_i          = 1'b1;
    instr_valid_i           = 1'b0;
    instr_rdata_i           = 32'h0000_0013; // NOP
    instr_rdata_alu_i       = instr_rdata_i;
    instr_rdata_c_i         = instr_rdata_i[15:0];
    instr_is_compressed_i   = 1'b0;
    branch_decision_i       = 1'b0;
    illegal_c_insn_i        = 1'b0;
    instr_fetch_err_i       = 1'b0;
    instr_fetch_err_plus2_i = 1'b0;
    pc_id_i                 = '0;
    ex_valid_i              = 1'b1;
    lsu_resp_valid_i        = 1'b1;
    imd_val_we_ex_i         = 2'b00;
    imd_val_d_ex_i[0]       = '0;
    imd_val_d_ex_i[1]       = '0;
    lsu_addr_incr_req_i     = 1'b0;
    lsu_addr_last_i         = '0;
    csr_mstatus_mie_i       = 1'b0;
    irq_pending_i           = 1'b0;
    irqs_i                  = '0;
    irq_nm_i                = 1'b0;
    lsu_load_err_i          = 1'b0;
    lsu_store_err_i         = 1'b0;
    priv_mode_i             = PRIV_LVL_M;
    csr_mstatus_tw_i        = 1'b0;
    illegal_csr_insn_i      = 1'b0;
    debug_req_i             = 1'b0;
    debug_single_step_i     = 1'b0;
    debug_ebreakm_i         = 1'b0;
    debug_ebreaku_i         = 1'b0;
    trigger_match_i         = 1'b0;
    result_ex_i             = '0;
    csr_rdata_i             = '0;
    rf_rdata_a_i            = '0;
    rf_rdata_b_i            = '0;
  endtask

  task automatic drive_dret_instruction;
    instr_valid_i         = 1'b1;
    instr_rdata_i         = DRET_INSN;
    instr_rdata_alu_i     = DRET_INSN;
    instr_rdata_c_i       = DRET_INSN[15:0];
    instr_is_compressed_i = 1'b0;
  endtask

  // Patch-related coverage: DRET should not count for minstret when not in debug mode
  // [verilator-strip cg] covergroup cg_dret_minstret @(posedge clk);
// [verilator-strip cg]     option.per_instance = 1;

// [verilator-strip cg]     cp_dret_insn: coverpoint (instr_rdata_i == DRET_INSN && instr_valid_i) {
// [verilator-strip cg]       bins dret_active = {1};
// [verilator-strip cg]       bins not_dret = {0};
// [verilator-strip cg]     }

// [verilator-strip cg]     cp_debug_mode: coverpoint debug_mode_o {
// [verilator-strip cg]       // in_debug is unreachable in this unit-level testbench (no debug entry path)
// [verilator-strip cg]       ignore_bins ig_in_debug = {1};
// [verilator-strip cg]       bins not_in_debug = {0};
// [verilator-strip cg]     }

// [verilator-strip cg]     cp_perf_count: coverpoint instr_perf_count_id_o {
// [verilator-strip cg]       bins counted = {1};
// [verilator-strip cg]       bins not_counted = {0};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cross: DRET outside debug mode should NOT be counted
// [verilator-strip cg]     cx_dret_no_debug: cross cp_dret_insn, cp_debug_mode, cp_perf_count {
// [verilator-strip cg]       bins dret_nodebug_nocnt = binsof(cp_dret_insn.dret_active) &&
// [verilator-strip cg]                                  binsof(cp_debug_mode.not_in_debug) &&
// [verilator-strip cg]                                  binsof(cp_perf_count.not_counted);
// [verilator-strip cg]       ignore_bins ig_others = !binsof(cp_dret_insn.dret_active) ||
// [verilator-strip cg]                                !binsof(cp_debug_mode.not_in_debug) ||
// [verilator-strip cg]                                !binsof(cp_perf_count.not_counted);
// [verilator-strip cg]     }
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_dret_minstret cg_inst = new();

  initial begin
    drive_defaults();

    repeat (5) @(posedge clk);
    rst_ni = 1'b1;
    repeat (3) @(posedge clk);

    // First send a NOP to hit perf_count = counted
    instr_valid_i   = 1'b1;
    instr_rdata_i   = 32'h0000_0013; // NOP (ADDI x0, x0, 0)
    instr_rdata_alu_i = 32'h0000_0013;
    instr_rdata_c_i = 16'h0013;
    instr_is_compressed_i = 1'b0;
    repeat (3) @(posedge clk);
    instr_valid_i = 1'b0;
    repeat (2) @(posedge clk);

    drive_dret_instruction();
    repeat (3) @(posedge clk);

    if (instr_perf_count_id_o !== 1'b0) begin
      $fatal(1, "FAIL: DRET without debug mode still counted as retired instruction.");
      $finish;
    end

    $display("PASS: DRET without debug mode does not increment minstret.");
    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end


  initial begin
    $dumpfile("tb_cve2_dret_minstret_patch.vcd");
    $dumpvars(0);
  end

endmodule

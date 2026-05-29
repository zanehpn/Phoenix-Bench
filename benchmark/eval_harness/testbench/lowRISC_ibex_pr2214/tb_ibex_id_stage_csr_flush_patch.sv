// Testbench for lowRISC/ibex PR #2214
// Verifies that the pipeline flush logic correctly handles all CSR operations
// (WRITE, SET, CLEAR) and all CSR address categories.
//
// The bug (issue #2193): CSR_OP_CLEAR on PMP registers did NOT trigger a
// pipeline flush, allowing stale PMP checks to pass for fetched instructions.
//
// The fix: flush the pipeline on ANY CSR modification (WRITE/SET/CLEAR),
// except for CSR_MSCRATCH and CSR_MEPC which are safe to skip.

module tb_ibex_id_stage_csr_flush_patch;

  import ibex_pkg::*;

  // -------------------------
  // Clock & Reset
  // -------------------------
  logic clk, rst_ni;
  always #5 clk = ~clk;

  // -------------------------
  // Counters
  // -------------------------
  int pass_count = 0;
  int fail_count = 0;
  int test_count = 0;

  // -------------------------
  // DUT IO declarations
  // -------------------------
  logic        instr_valid_i;
  logic [31:0] instr_rdata_i;
  logic [31:0] instr_rdata_alu_i;
  logic [15:0] instr_rdata_c_i;
  logic        instr_is_compressed_i;
  logic        instr_bp_taken_i;

  logic                csr_access_o;
  ibex_pkg::csr_op_e   csr_op_o;
  ibex_pkg::csr_num_e  csr_addr_o;
  logic                csr_op_en_o;
  logic                illegal_insn_o;

  // -------------------------
  // Instantiate DUT (patched ibex_id_stage with csr_addr_o)
  // -------------------------
  ibex_id_stage dut (
      .clk_i(clk),
      .rst_ni(rst_ni),

      .ctrl_busy_o(),
      .illegal_insn_o(illegal_insn_o),

      // IF -> ID pipeline
      .instr_valid_i(instr_valid_i),
      .instr_rdata_i(instr_rdata_i),
      .instr_rdata_alu_i(instr_rdata_alu_i),
      .instr_rdata_c_i(instr_rdata_c_i),
      .instr_is_compressed_i(instr_is_compressed_i),
      .instr_bp_taken_i(instr_bp_taken_i),

      .instr_req_o(),
      .instr_first_cycle_id_o(),
      .instr_valid_clear_o(),
      .id_in_ready_o(),
      .instr_exec_i(1'b1),
      .icache_inval_o(),

      // Jumps / Exceptions
      .pc_set_o(),
      .pc_mux_o(),
      .nt_branch_mispredict_o(),
      .nt_branch_addr_o(),
      .exc_pc_mux_o(),
      .exc_cause_o(),
      .branch_decision_i(1'b0),

      // Errors
      .illegal_c_insn_i(1'b0),
      .instr_fetch_err_i(1'b0),
      .instr_fetch_err_plus2_i(1'b0),
      .pc_id_i(32'h0),

      // Stalls
      .ex_valid_i(1'b1),
      .lsu_resp_valid_i(1'b1),

      // ALU
      .alu_operator_ex_o(),
      .alu_operand_a_ex_o(),
      .alu_operand_b_ex_o(),

      // Multicycle
      .imd_val_we_ex_i(2'b0),
      .imd_val_d_ex_i('{default: '0}),
      .imd_val_q_ex_o(),

      // Branch target ALU
      .bt_a_operand_o(),
      .bt_b_operand_o(),

      // MUL/DIV
      .mult_en_ex_o(),
      .div_en_ex_o(),
      .mult_sel_ex_o(),
      .div_sel_ex_o(),
      .multdiv_operator_ex_o(),
      .multdiv_signed_mode_ex_o(),
      .multdiv_operand_a_ex_o(),
      .multdiv_operand_b_ex_o(),
      .multdiv_ready_id_o(),

      // CSR block
      .csr_access_o(csr_access_o),
      .csr_op_o(csr_op_o),
      .csr_addr_o(csr_addr_o),
      .csr_op_en_o(csr_op_en_o),
      .csr_save_if_o(),
      .csr_save_id_o(),
      .csr_save_wb_o(),
      .csr_restore_mret_id_o(),
      .csr_restore_dret_id_o(),
      .csr_save_cause_o(),
      .csr_mtval_o(),
      .priv_mode_i(ibex_pkg::PRIV_LVL_M),
      .csr_mstatus_tw_i(1'b0),
      .illegal_csr_insn_i(1'b0),
      .data_ind_timing_i(1'b0),

      // LSU
      .lsu_req_o(),
      .lsu_we_o(),
      .lsu_type_o(),
      .lsu_sign_ext_o(),
      .lsu_wdata_o(),
      .lsu_req_done_i(1'b0),
      .lsu_addr_incr_req_i(1'b0),
      .lsu_addr_last_i(32'h0),

      // Interrupts
      .csr_mstatus_mie_i(1'b0),
      .irq_pending_i(1'b0),
      .irqs_i('{default:0}),
      .irq_nm_i(1'b0),
      .nmi_mode_o(),

      // LSU errors
      .lsu_load_err_i(1'b0),
      .lsu_load_resp_intg_err_i(1'b0),
      .lsu_store_err_i(1'b0),
      .lsu_store_resp_intg_err_i(1'b0),

      .expecting_load_resp_o(),
      .expecting_store_resp_o(),

      // Debug
      .debug_mode_o(),
      .debug_mode_entering_o(),
      .debug_cause_o(),
      .debug_csr_save_o(),
      .debug_req_i(1'b0),
      .debug_single_step_i(1'b0),
      .debug_ebreakm_i(1'b0),
      .debug_ebreaku_i(1'b0),
      .trigger_match_i(1'b0),

      // WB
      .result_ex_i(32'h0),
      .csr_rdata_i(32'h0),

      // RF
      .rf_raddr_a_o(),
      .rf_rdata_a_i(32'h0),
      .rf_raddr_b_o(),
      .rf_rdata_b_i(32'h0),
      .rf_ren_a_o(),
      .rf_ren_b_o(),

      .rf_waddr_id_o(),
      .rf_wdata_id_o(),
      .rf_we_id_o(),
      .rf_rd_a_wb_match_o(),
      .rf_rd_b_wb_match_o(),
      .rf_waddr_wb_i(5'h0),
      .rf_wdata_fwd_wb_i(32'h0),
      .rf_write_wb_i(1'b0),

      .en_wb_o(),
      .instr_type_wb_o(),
      .instr_perf_count_id_o(),
      .ready_wb_i(1'b1),
      .outstanding_load_wb_i(1'b0),
      .outstanding_store_wb_i(1'b0),

      // Performance counters
      .perf_jump_o(),
      .perf_branch_o(),
      .perf_tbranch_o(),
      .perf_dside_wait_o(),
      .perf_mul_wait_o(),
      .perf_div_wait_o(),
      .instr_id_done_o()
  );

  // -------------------------
  // Patch-focused coverage
  // -------------------------
  wire csr_pipe_flush_w   = dut.csr_pipe_flush;
  wire no_flush_csr_addr_w = dut.no_flush_csr_addr;

  covergroup cg_patch;
    cp_csr_op: coverpoint csr_op_o {
      bins write = {CSR_OP_WRITE};
      bins set   = {CSR_OP_SET};
      bins clear = {CSR_OP_CLEAR};
      bins read  = {CSR_OP_READ};
    }
    // op_en is implicitly tested by the flush logic but not directly a patch concern
    cp_csr_op_en: coverpoint csr_op_en_o {
      bins enabled  = {1'b1};
      // op_en=0 is forced between clock edges and may not be captured at posedge sampling
      ignore_bins disabled = {1'b0};
    }
    cp_pipe_flush: coverpoint csr_pipe_flush_w;
    cp_no_flush_addr: coverpoint no_flush_csr_addr_w;
    cx_op_flush: cross cp_csr_op, cp_pipe_flush {
      // READ never causes a flush
      ignore_bins read_flush = binsof(cp_csr_op.read) && binsof(cp_pipe_flush) intersect {1};
    }
    cx_no_flush: cross cp_no_flush_addr, cp_csr_op, cp_pipe_flush {
      // READ never flushes regardless of address
      ignore_bins read_flush = binsof(cp_csr_op.read) && binsof(cp_pipe_flush) intersect {1};
      // no_flush_addr=1 (MSCRATCH/MEPC) never flushes even on write/set/clear
      ignore_bins noflush_addr_flush = binsof(cp_no_flush_addr) intersect {1} && binsof(cp_pipe_flush) intersect {1};
      // no_flush_addr=0 + read + flush=0 is a valid scenario (reads never flush)
      // no_flush_addr=1 + read + flush=0 is also valid
      // no_flush_addr=0 + write/set/clear + flush=0 can happen when op_en=0 (tested in category 4)
    }
  endgroup

  cg_patch cg_inst = new();

  always @(posedge clk) begin
    if (rst_ni) cg_inst.sample();
  end

  // -------------------------
  // Helper: build a CSRRW/CSRRS/CSRRC instruction
  // -------------------------
  // RISC-V CSR instruction format: [csr_addr(12)][rs1(5)][funct3(3)][rd(5)][opcode(7)]
  // CSRRW: funct3 = 3'b001, opcode = 7'b1110011
  // CSRRS: funct3 = 3'b010, opcode = 7'b1110011
  // CSRRC: funct3 = 3'b011, opcode = 7'b1110011
  // CSRRWI: funct3 = 3'b101, opcode = 7'b1110011
  // CSRRSI: funct3 = 3'b110, opcode = 7'b1110011
  // CSRRCI: funct3 = 3'b111, opcode = 7'b1110011
  function automatic [31:0] build_csr_instr(
      input [11:0] csr_addr,
      input [2:0]  funct3,
      input [4:0]  rs1,
      input [4:0]  rd
  );
    return {csr_addr, rs1, funct3, rd, 7'b1110011};
  endfunction

  // Map CSR_OP_e to the register-based funct3 encoding
  function automatic [2:0] csr_op_to_funct3(input csr_op_e op);
    case (op)
      CSR_OP_WRITE: return 3'b001; // CSRRW
      CSR_OP_SET:   return 3'b010; // CSRRS
      CSR_OP_CLEAR: return 3'b011; // CSRRC
      CSR_OP_READ:  return 3'b010; // CSRRS with rs1=x0 => read-only
      default:      return 3'b001;
    endcase
  endfunction

  // Map CSR_OP_e to the immediate-based funct3 encoding
  function automatic [2:0] csr_op_to_imm_funct3(input csr_op_e op);
    case (op)
      CSR_OP_WRITE: return 3'b101; // CSRRWI
      CSR_OP_SET:   return 3'b110; // CSRRSI
      CSR_OP_CLEAR: return 3'b111; // CSRRCI
      default:      return 3'b101;
    endcase
  endfunction

  // Module-level signals for force operations (VCS does not allow
  // automatic task variables in force statements)
  csr_op_e   force_csr_op;
  logic      force_csr_op_en;

  // -------------------------
  // Check task: forces csr_op_en_o and csr_op_o, then checks csr_pipe_flush
  // -------------------------
  task automatic check_flush(
      input string       test_name,
      input [11:0]       csr_addr,
      input csr_op_e     op,
      input bit          expect_flush
  );
    logic actual_flush;
    logic [2:0] funct3;
    logic [4:0] rs1_val;

    test_count++;

    // For CSR_OP_READ via CSRRS, rs1 must be x0 to indicate read-only
    if (op == CSR_OP_READ) begin
      funct3 = 3'b010; // CSRRS
      rs1_val = 5'b0;  // rs1 = x0 makes it a read
    end else begin
      funct3 = csr_op_to_funct3(op);
      rs1_val = 5'd1; // non-zero rs1
    end

    // Drive instruction and valid
    instr_rdata_i     = build_csr_instr(csr_addr, funct3, rs1_val, 5'd1);
    instr_rdata_alu_i = instr_rdata_i;
    instr_valid_i     = 1'b1;

    // Force the CSR operation enable and op type directly, since the decoder
    // path through controller may not naturally enable csr_op_en_o in this
    // unit-test setup
    force_csr_op    = op;
    force_csr_op_en = 1'b1;
    force dut.csr_op_en_o = force_csr_op_en;
    force dut.csr_op_o    = force_csr_op;

    #1; // let combinational logic settle
    cg_inst.sample();  // explicitly sample with forced values

    actual_flush = dut.csr_pipe_flush;

    if (actual_flush !== expect_flush) begin
      $display("FAIL [%0d]: %s | CSR=0x%03h op=%s | expected flush=%0b got=%0b",
               test_count, test_name, csr_addr, op.name(), expect_flush, actual_flush);
      fail_count++;
    end else begin
      $display("PASS [%0d]: %s | CSR=0x%03h op=%s | flush=%0b",
               test_count, test_name, csr_addr, op.name(), actual_flush);
      pass_count++;
    end

    // Release forces
    release dut.csr_op_en_o;
    release dut.csr_op_o;
    instr_valid_i = 1'b0;
    #1;
  endtask

  // -------------------------
  // Check task with csr_op_en_o disabled
  // -------------------------
  task automatic check_no_flush_when_disabled(
      input string       test_name,
      input [11:0]       csr_addr,
      input csr_op_e     op
  );
    logic actual_flush;
    logic [2:0] funct3;

    test_count++;

    funct3 = csr_op_to_funct3(op);
    instr_rdata_i     = build_csr_instr(csr_addr, funct3, 5'd1, 5'd1);
    instr_rdata_alu_i = instr_rdata_i;
    instr_valid_i     = 1'b1;
    force_csr_op    = op;
    force_csr_op_en = 1'b0;
    force dut.csr_op_en_o = force_csr_op_en;
    force dut.csr_op_o    = force_csr_op;
    #1;
    actual_flush = dut.csr_pipe_flush;
    if (actual_flush !== 1'b0) begin
      $display("FAIL [%0d]: %s (op_en=0) | CSR=0x%03h op=%s | expected flush=0 got=%0b",
               test_count, test_name, csr_addr, op.name(), actual_flush);
      fail_count++;
    end else begin
      $display("PASS [%0d]: %s (op_en=0) | CSR=0x%03h op=%s | flush=0",
               test_count, test_name, csr_addr, op.name());
      pass_count++;
    end
    release dut.csr_op_en_o;
    release dut.csr_op_o;
    instr_valid_i = 1'b0;
    #1;
  endtask

  // -------------------------
  // Check task for immediate-form CSR instructions (CSRRWI/CSRRSI/CSRRCI)
  // -------------------------
  task automatic check_flush_imm(
      input string       test_name,
      input [11:0]       csr_addr,
      input csr_op_e     op,
      input [4:0]        imm_val,
      input bit          expect_flush
  );
    logic actual_flush;
    logic [2:0] funct3;

    test_count++;

    funct3 = csr_op_to_imm_funct3(op);
    instr_rdata_i     = build_csr_instr(csr_addr, funct3, imm_val, 5'd1);
    instr_rdata_alu_i = instr_rdata_i;
    instr_valid_i     = 1'b1;
    force_csr_op    = op;
    force_csr_op_en = 1'b1;
    force dut.csr_op_en_o = force_csr_op_en;
    force dut.csr_op_o    = force_csr_op;
    #1;
    actual_flush = dut.csr_pipe_flush;

    if (actual_flush !== expect_flush) begin
      $display("FAIL [%0d]: %s | CSR=0x%03h op=%s imm=%0d | expected flush=%0b got=%0b",
               test_count, test_name, csr_addr, op.name(), imm_val, expect_flush, actual_flush);
      fail_count++;
    end else begin
      $display("PASS [%0d]: %s | CSR=0x%03h op=%s imm=%0d | flush=%0b",
               test_count, test_name, csr_addr, op.name(), imm_val, actual_flush);
      pass_count++;
    end

    release dut.csr_op_en_o;
    release dut.csr_op_o;
    instr_valid_i = 1'b0;
    #1;
  endtask

  // -------------------------
  // Check no_flush_csr_addr signal directly
  // -------------------------
  task automatic check_no_flush_addr_signal(
      input string       test_name,
      input [11:0]       csr_addr,
      input bit          expect_no_flush
  );
    logic no_flush_val;

    test_count++;
    instr_rdata_i     = build_csr_instr(csr_addr, 3'b001, 5'd1, 5'd1);
    instr_rdata_alu_i = instr_rdata_i;
    instr_valid_i     = 1'b1;
    #1;
    no_flush_val = dut.no_flush_csr_addr;
    if (no_flush_val !== expect_no_flush) begin
      $display("FAIL [%0d]: no_flush_csr_addr %s | CSR=0x%03h | expected=%0b got=%0b",
               test_count, test_name, csr_addr, expect_no_flush, no_flush_val);
      fail_count++;
    end else begin
      $display("PASS [%0d]: no_flush_csr_addr %s | CSR=0x%03h | val=%0b",
               test_count, test_name, csr_addr, no_flush_val);
      pass_count++;
    end
    instr_valid_i = 1'b0;
    #1;
  endtask

  // -------------------------
  // Check csr_addr_o output correctness
  // -------------------------
  task automatic check_csr_addr_output(
      input string       test_name,
      input [11:0]       csr_addr,
      input [2:0]        funct3
  );
    test_count++;
    instr_rdata_i     = build_csr_instr(csr_addr, funct3, 5'd1, 5'd1);
    instr_rdata_alu_i = instr_rdata_i;
    instr_valid_i     = 1'b1;
    #1;

    if (csr_addr_o !== csr_num_e'(csr_addr)) begin
      $display("FAIL [%0d]: csr_addr_o %s | expected=0x%03h got=0x%03h",
               test_count, test_name, csr_addr, csr_addr_o);
      fail_count++;
    end else begin
      $display("PASS [%0d]: csr_addr_o %s | val=0x%03h", test_count, test_name, csr_addr_o);
      pass_count++;
    end

    instr_valid_i = 1'b0;
    #1;
  endtask

  // -------------------------
  // Test sequence
  // -------------------------
  initial begin
    clk   = 0;
    rst_ni = 0;
    instr_valid_i = 0;
    instr_rdata_i = 32'h0;
    instr_rdata_alu_i = 32'h0;
    instr_rdata_c_i = 16'h0;
    instr_is_compressed_i = 0;
    instr_bp_taken_i = 0;

    // Hold reset for a few cycles
    repeat (4) @(posedge clk);
    rst_ni = 1;
    repeat (2) @(posedge clk);

    $display("\n==========================================================");
    $display("  Testing CSR pipeline flush fix (PR #2214 / Issue #2193)");
    $display("==========================================================\n");

    // ============================================================
    // CATEGORY 1: CSRs that MUST flush (most CSRs)
    // Test all three modification operations: WRITE, SET, CLEAR
    // ============================================================

    $display("--- Category 1a: MSTATUS - interrupt/privilege related ---");
    check_flush("MSTATUS WRITE", CSR_MSTATUS, CSR_OP_WRITE, 1);
    check_flush("MSTATUS SET",   CSR_MSTATUS, CSR_OP_SET,   1);
    check_flush("MSTATUS CLEAR", CSR_MSTATUS, CSR_OP_CLEAR, 1);

    $display("--- Category 1b: MIE - interrupt enable ---");
    check_flush("MIE WRITE", CSR_MIE, CSR_OP_WRITE, 1);
    check_flush("MIE SET",   CSR_MIE, CSR_OP_SET,   1);
    check_flush("MIE CLEAR", CSR_MIE, CSR_OP_CLEAR, 1);

    $display("--- Category 1c: MSECCFG - PMP security config ---");
    check_flush("MSECCFG WRITE", CSR_MSECCFG, CSR_OP_WRITE, 1);
    check_flush("MSECCFG SET",   CSR_MSECCFG, CSR_OP_SET,   1);
    check_flush("MSECCFG CLEAR", CSR_MSECCFG, CSR_OP_CLEAR, 1);

    // ============================================================
    // CATEGORY 1d: PMP config registers - THE KEY BUG SCENARIO
    // Pre-patch: CSR_OP_CLEAR on PMP regs did NOT flush!
    // ============================================================
    $display("\n--- Category 1d: PMP config registers (key bug scenario) ---");

    // All PMPCFG registers with all three operations
    check_flush("PMPCFG0 WRITE", CSR_PMPCFG0, CSR_OP_WRITE, 1);
    check_flush("PMPCFG0 SET",   CSR_PMPCFG0, CSR_OP_SET,   1);
    check_flush("PMPCFG0 CLEAR", CSR_PMPCFG0, CSR_OP_CLEAR, 1); // BUG: was not flushing

    check_flush("PMPCFG1 WRITE", CSR_PMPCFG1, CSR_OP_WRITE, 1);
    check_flush("PMPCFG1 SET",   CSR_PMPCFG1, CSR_OP_SET,   1);
    check_flush("PMPCFG1 CLEAR", CSR_PMPCFG1, CSR_OP_CLEAR, 1); // BUG: was not flushing

    check_flush("PMPCFG2 WRITE", CSR_PMPCFG2, CSR_OP_WRITE, 1);
    check_flush("PMPCFG2 SET",   CSR_PMPCFG2, CSR_OP_SET,   1);
    check_flush("PMPCFG2 CLEAR", CSR_PMPCFG2, CSR_OP_CLEAR, 1); // BUG: was not flushing

    check_flush("PMPCFG3 WRITE", CSR_PMPCFG3, CSR_OP_WRITE, 1);
    check_flush("PMPCFG3 SET",   CSR_PMPCFG3, CSR_OP_SET,   1);
    check_flush("PMPCFG3 CLEAR", CSR_PMPCFG3, CSR_OP_CLEAR, 1); // BUG: was not flushing

    // ============================================================
    // CATEGORY 1e: ALL PMP address registers with CLEAR
    // This is the exact bug scenario - sweep all 16 PMPADDR regs
    // ============================================================
    $display("\n--- Category 1e: All PMP address registers (exhaustive CLEAR sweep) ---");

    check_flush("PMPADDR0 CLEAR",  CSR_PMPADDR0,  CSR_OP_CLEAR, 1);
    check_flush("PMPADDR1 CLEAR",  CSR_PMPADDR1,  CSR_OP_CLEAR, 1);
    check_flush("PMPADDR2 CLEAR",  CSR_PMPADDR2,  CSR_OP_CLEAR, 1);
    check_flush("PMPADDR3 CLEAR",  CSR_PMPADDR3,  CSR_OP_CLEAR, 1);
    check_flush("PMPADDR4 CLEAR",  CSR_PMPADDR4,  CSR_OP_CLEAR, 1);
    check_flush("PMPADDR5 CLEAR",  CSR_PMPADDR5,  CSR_OP_CLEAR, 1);
    check_flush("PMPADDR6 CLEAR",  CSR_PMPADDR6,  CSR_OP_CLEAR, 1);
    check_flush("PMPADDR7 CLEAR",  CSR_PMPADDR7,  CSR_OP_CLEAR, 1);
    check_flush("PMPADDR8 CLEAR",  CSR_PMPADDR8,  CSR_OP_CLEAR, 1);
    check_flush("PMPADDR9 CLEAR",  CSR_PMPADDR9,  CSR_OP_CLEAR, 1);
    check_flush("PMPADDR10 CLEAR", CSR_PMPADDR10, CSR_OP_CLEAR, 1);
    check_flush("PMPADDR11 CLEAR", CSR_PMPADDR11, CSR_OP_CLEAR, 1);
    check_flush("PMPADDR12 CLEAR", CSR_PMPADDR12, CSR_OP_CLEAR, 1);
    check_flush("PMPADDR13 CLEAR", CSR_PMPADDR13, CSR_OP_CLEAR, 1);
    check_flush("PMPADDR14 CLEAR", CSR_PMPADDR14, CSR_OP_CLEAR, 1);
    check_flush("PMPADDR15 CLEAR", CSR_PMPADDR15, CSR_OP_CLEAR, 1);

    // Boundary PMP address registers with WRITE and SET too
    check_flush("PMPADDR0 WRITE",  CSR_PMPADDR0,  CSR_OP_WRITE, 1);
    check_flush("PMPADDR0 SET",    CSR_PMPADDR0,  CSR_OP_SET,   1);
    check_flush("PMPADDR15 WRITE", CSR_PMPADDR15, CSR_OP_WRITE, 1);
    check_flush("PMPADDR15 SET",   CSR_PMPADDR15, CSR_OP_SET,   1);
    check_flush("PMPADDR8 SET",    CSR_PMPADDR8,  CSR_OP_SET,   1);

    // ============================================================
    // CATEGORY 1f: Debug CSRs - must flush on all modifications
    // Pre-patch: only flushed on non-READ (CLEAR was included for
    // debug CSRs but not for PMP) - post-patch treated uniformly
    // ============================================================
    $display("\n--- Category 1f: Debug CSRs ---");

    check_flush("DCSR WRITE",      CSR_DCSR,      CSR_OP_WRITE, 1);
    check_flush("DCSR SET",        CSR_DCSR,      CSR_OP_SET,   1);
    check_flush("DCSR CLEAR",      CSR_DCSR,      CSR_OP_CLEAR, 1);
    check_flush("DPC WRITE",       CSR_DPC,       CSR_OP_WRITE, 1);
    check_flush("DPC SET",         CSR_DPC,       CSR_OP_SET,   1);
    check_flush("DPC CLEAR",       CSR_DPC,       CSR_OP_CLEAR, 1);
    check_flush("DSCRATCH0 WRITE", CSR_DSCRATCH0, CSR_OP_WRITE, 1);
    check_flush("DSCRATCH0 SET",   CSR_DSCRATCH0, CSR_OP_SET,   1);
    check_flush("DSCRATCH0 CLEAR", CSR_DSCRATCH0, CSR_OP_CLEAR, 1);
    check_flush("DSCRATCH1 WRITE", CSR_DSCRATCH1, CSR_OP_WRITE, 1);
    check_flush("DSCRATCH1 SET",   CSR_DSCRATCH1, CSR_OP_SET,   1);
    check_flush("DSCRATCH1 CLEAR", CSR_DSCRATCH1, CSR_OP_CLEAR, 1);

    // ============================================================
    // CATEGORY 1g: Other CSRs that now flush (new behavior: flush
    // on all CSR modifications except MSCRATCH and MEPC)
    // ============================================================
    $display("\n--- Category 1g: Other CSRs (now flush under new policy) ---");

    check_flush("MCAUSE WRITE", CSR_MCAUSE, CSR_OP_WRITE, 1);
    check_flush("MCAUSE SET",   CSR_MCAUSE, CSR_OP_SET,   1);
    check_flush("MCAUSE CLEAR", CSR_MCAUSE, CSR_OP_CLEAR, 1);

    check_flush("MTVAL WRITE",  CSR_MTVAL,  CSR_OP_WRITE, 1);
    check_flush("MTVAL SET",    CSR_MTVAL,  CSR_OP_SET,   1);
    check_flush("MTVAL CLEAR",  CSR_MTVAL,  CSR_OP_CLEAR, 1);

    check_flush("MTVEC WRITE",  CSR_MTVEC,  CSR_OP_WRITE, 1);
    check_flush("MTVEC SET",    CSR_MTVEC,  CSR_OP_SET,   1);
    check_flush("MTVEC CLEAR",  CSR_MTVEC,  CSR_OP_CLEAR, 1);

    check_flush("MCOUNTINHIBIT WRITE", CSR_MCOUNTINHIBIT, CSR_OP_WRITE, 1);
    check_flush("MCOUNTINHIBIT SET",   CSR_MCOUNTINHIBIT, CSR_OP_SET,   1);
    check_flush("MCOUNTINHIBIT CLEAR", CSR_MCOUNTINHIBIT, CSR_OP_CLEAR, 1);

    check_flush("MIP WRITE",      CSR_MIP,      CSR_OP_WRITE, 1);
    check_flush("MISA WRITE",     CSR_MISA,     CSR_OP_WRITE, 1);
    check_flush("MISA CLEAR",     CSR_MISA,     CSR_OP_CLEAR, 1);
    check_flush("MSTATUSH WRITE", CSR_MSTATUSH, CSR_OP_WRITE, 1);
    check_flush("MENVCFG WRITE",  CSR_MENVCFG,  CSR_OP_WRITE, 1);
    check_flush("MENVCFGH WRITE", CSR_MENVCFGH, CSR_OP_WRITE, 1);
    check_flush("MCOUNTEREN WRITE", CSR_MCOUNTEREN, CSR_OP_WRITE, 1);

    // Trigger/trace CSRs
    check_flush("TSELECT WRITE", CSR_TSELECT, CSR_OP_WRITE, 1);
    check_flush("TDATA1 WRITE",  CSR_TDATA1,  CSR_OP_WRITE, 1);
    check_flush("TDATA2 WRITE",  CSR_TDATA2,  CSR_OP_WRITE, 1);
    check_flush("TDATA3 WRITE",  CSR_TDATA3,  CSR_OP_WRITE, 1);
    check_flush("MCONTEXT WRITE", CSR_MCONTEXT, CSR_OP_WRITE, 1);

    // MSECCFGH
    check_flush("MSECCFGH WRITE", CSR_MSECCFGH, CSR_OP_WRITE, 1);
    check_flush("MSECCFGH CLEAR", CSR_MSECCFGH, CSR_OP_CLEAR, 1);

    // HPM event CSRs
    check_flush("MHPMEVENT3 WRITE", CSR_MHPMEVENT3, CSR_OP_WRITE, 1);
    check_flush("MHPMEVENT3 CLEAR", CSR_MHPMEVENT3, CSR_OP_CLEAR, 1);

    // Read-only CSRs with forced WRITE (exercising the logic path)
    check_flush("MVENDORID WRITE", CSR_MVENDORID, CSR_OP_WRITE, 1);
    check_flush("MARCHID WRITE",   CSR_MARCHID,   CSR_OP_WRITE, 1);
    check_flush("MHARTID WRITE",   CSR_MHARTID,   CSR_OP_WRITE, 1);

    // ============================================================
    // CATEGORY 2: CSRs that must NOT flush (MSCRATCH, MEPC)
    // These are commonly modified in exception handlers and are
    // safe to alter without a flush.
    // ============================================================
    $display("\n--- Category 2: CSRs that must NOT flush (MSCRATCH, MEPC) ---");

    check_flush("MSCRATCH WRITE", CSR_MSCRATCH, CSR_OP_WRITE, 0);
    check_flush("MSCRATCH SET",   CSR_MSCRATCH, CSR_OP_SET,   0);
    check_flush("MSCRATCH CLEAR", CSR_MSCRATCH, CSR_OP_CLEAR, 0);

    check_flush("MEPC WRITE", CSR_MEPC, CSR_OP_WRITE, 0);
    check_flush("MEPC SET",   CSR_MEPC, CSR_OP_SET,   0);
    check_flush("MEPC CLEAR", CSR_MEPC, CSR_OP_CLEAR, 0);

    // ============================================================
    // CATEGORY 3: CSR_OP_READ must NEVER flush (regardless of addr)
    // Read operations do not modify CSR state.
    // ============================================================
    $display("\n--- Category 3: CSR_OP_READ must never flush ---");

    check_flush("MSTATUS READ",  CSR_MSTATUS,  CSR_OP_READ, 0);
    check_flush("PMPCFG0 READ",  CSR_PMPCFG0,  CSR_OP_READ, 0);
    check_flush("PMPADDR0 READ", CSR_PMPADDR0, CSR_OP_READ, 0);
    check_flush("PMPADDR15 READ",CSR_PMPADDR15,CSR_OP_READ, 0);
    check_flush("DCSR READ",     CSR_DCSR,     CSR_OP_READ, 0);
    check_flush("MSCRATCH READ", CSR_MSCRATCH, CSR_OP_READ, 0);
    check_flush("MEPC READ",     CSR_MEPC,     CSR_OP_READ, 0);
    check_flush("MCAUSE READ",   CSR_MCAUSE,   CSR_OP_READ, 0);
    check_flush("MIE READ",      CSR_MIE,      CSR_OP_READ, 0);
    check_flush("MSECCFG READ",  CSR_MSECCFG,  CSR_OP_READ, 0);
    check_flush("MTVEC READ",    CSR_MTVEC,    CSR_OP_READ, 0);
    check_flush("MTVAL READ",    CSR_MTVAL,    CSR_OP_READ, 0);
    check_flush("TSELECT READ",  CSR_TSELECT,  CSR_OP_READ, 0);
    check_flush("TDATA1 READ",   CSR_TDATA1,   CSR_OP_READ, 0);

    // ============================================================
    // CATEGORY 4: csr_op_en_o = 0 must NEVER flush
    // Even if the CSR op is WRITE/SET/CLEAR, if the op is not
    // enabled, no flush should occur.
    // ============================================================
    $display("\n--- Category 4: csr_op_en_o=0 must never flush ---");

    check_no_flush_when_disabled("MSTATUS WRITE disabled",  CSR_MSTATUS,  CSR_OP_WRITE);
    check_no_flush_when_disabled("MSTATUS SET disabled",    CSR_MSTATUS,  CSR_OP_SET);
    check_no_flush_when_disabled("MSTATUS CLEAR disabled",  CSR_MSTATUS,  CSR_OP_CLEAR);
    check_no_flush_when_disabled("PMPCFG0 WRITE disabled",  CSR_PMPCFG0,  CSR_OP_WRITE);
    check_no_flush_when_disabled("PMPCFG0 CLEAR disabled",  CSR_PMPCFG0,  CSR_OP_CLEAR);
    check_no_flush_when_disabled("PMPADDR0 CLEAR disabled", CSR_PMPADDR0, CSR_OP_CLEAR);
    check_no_flush_when_disabled("PMPADDR15 CLEAR disabled",CSR_PMPADDR15,CSR_OP_CLEAR);
    check_no_flush_when_disabled("DCSR WRITE disabled",     CSR_DCSR,     CSR_OP_WRITE);
    check_no_flush_when_disabled("DPC CLEAR disabled",      CSR_DPC,      CSR_OP_CLEAR);
    check_no_flush_when_disabled("MSCRATCH WRITE disabled", CSR_MSCRATCH, CSR_OP_WRITE);
    check_no_flush_when_disabled("MEPC WRITE disabled",     CSR_MEPC,     CSR_OP_WRITE);
    check_no_flush_when_disabled("MCAUSE SET disabled",     CSR_MCAUSE,   CSR_OP_SET);
    check_no_flush_when_disabled("MTVEC WRITE disabled",    CSR_MTVEC,    CSR_OP_WRITE);
    check_no_flush_when_disabled("MIE CLEAR disabled",      CSR_MIE,      CSR_OP_CLEAR);
    check_no_flush_when_disabled("MSECCFG SET disabled",    CSR_MSECCFG,  CSR_OP_SET);

    // ============================================================
    // CATEGORY 5: Verify csr_addr_o output from decoder
    // The patch adds csr_addr_o directly from the instruction bits.
    // Verify it matches instr_rdata_i[31:20] for various CSR addrs.
    // ============================================================
    $display("\n--- Category 5: csr_addr_o correctness ---");

    check_csr_addr_output("MSTATUS via CSRRW",   CSR_MSTATUS,   3'b001);
    check_csr_addr_output("PMPCFG0 via CSRRS",   CSR_PMPCFG0,   3'b010);
    check_csr_addr_output("PMPADDR0 via CSRRC",  CSR_PMPADDR0,  3'b011);
    check_csr_addr_output("PMPADDR15 via CSRRW", CSR_PMPADDR15, 3'b001);
    check_csr_addr_output("MSCRATCH via CSRRW",  CSR_MSCRATCH,  3'b001);
    check_csr_addr_output("MEPC via CSRRW",      CSR_MEPC,      3'b001);
    check_csr_addr_output("DCSR via CSRRW",      CSR_DCSR,      3'b001);
    check_csr_addr_output("DPC via CSRRS",       CSR_DPC,       3'b010);
    check_csr_addr_output("DSCRATCH0 via CSRRC", CSR_DSCRATCH0, 3'b011);
    check_csr_addr_output("MCAUSE via CSRRW",    CSR_MCAUSE,    3'b001);
    check_csr_addr_output("MTVEC via CSRRW",     CSR_MTVEC,     3'b001);
    check_csr_addr_output("MIE via CSRRW",       CSR_MIE,       3'b001);
    check_csr_addr_output("MSECCFG via CSRRW",   CSR_MSECCFG,   3'b001);
    check_csr_addr_output("TSELECT via CSRRW",   CSR_TSELECT,   3'b001);

    // Immediate-form instructions should also set csr_addr_o correctly
    check_csr_addr_output("MSTATUS via CSRRWI",  CSR_MSTATUS,   3'b101);
    check_csr_addr_output("PMPCFG0 via CSRRSI",  CSR_PMPCFG0,   3'b110);
    check_csr_addr_output("PMPADDR0 via CSRRCI", CSR_PMPADDR0,  3'b111);
    check_csr_addr_output("MSCRATCH via CSRRWI", CSR_MSCRATCH,  3'b101);
    check_csr_addr_output("MEPC via CSRRCI",     CSR_MEPC,      3'b111);

    // Arbitrary 12-bit addresses (non-standard CSR numbers)
    check_csr_addr_output("Arbitrary 0x000",     12'h000,       3'b001);
    check_csr_addr_output("Arbitrary 0xFFF",     12'hFFF,       3'b001);
    check_csr_addr_output("Arbitrary 0xABC",     12'hABC,       3'b001);
    check_csr_addr_output("Arbitrary 0x123",     12'h123,       3'b010);

    // ============================================================
    // CATEGORY 6: no_flush_csr_addr signal
    // Verify the intermediate signal used in the flush equation
    // ============================================================
    $display("\n--- Category 6: no_flush_csr_addr signal check ---");

    // CSRs that should set no_flush_csr_addr = 1
    check_no_flush_addr_signal("MSCRATCH", CSR_MSCRATCH, 1);
    check_no_flush_addr_signal("MEPC",     CSR_MEPC,     1);

    // CSRs that should set no_flush_csr_addr = 0
    check_no_flush_addr_signal("MSTATUS",   CSR_MSTATUS,   0);
    check_no_flush_addr_signal("PMPCFG0",   CSR_PMPCFG0,   0);
    check_no_flush_addr_signal("PMPCFG3",   CSR_PMPCFG3,   0);
    check_no_flush_addr_signal("PMPADDR0",  CSR_PMPADDR0,  0);
    check_no_flush_addr_signal("PMPADDR15", CSR_PMPADDR15, 0);
    check_no_flush_addr_signal("MIE",       CSR_MIE,       0);
    check_no_flush_addr_signal("MSECCFG",   CSR_MSECCFG,   0);
    check_no_flush_addr_signal("DCSR",      CSR_DCSR,      0);
    check_no_flush_addr_signal("DPC",       CSR_DPC,       0);
    check_no_flush_addr_signal("DSCRATCH0", CSR_DSCRATCH0, 0);
    check_no_flush_addr_signal("DSCRATCH1", CSR_DSCRATCH1, 0);
    check_no_flush_addr_signal("MCAUSE",    CSR_MCAUSE,    0);
    check_no_flush_addr_signal("MTVAL",     CSR_MTVAL,     0);
    check_no_flush_addr_signal("MTVEC",     CSR_MTVEC,     0);
    check_no_flush_addr_signal("MCOUNTINHIBIT", CSR_MCOUNTINHIBIT, 0);
    check_no_flush_addr_signal("MIP",       CSR_MIP,       0);
    // Addresses near MSCRATCH/MEPC but different
    check_no_flush_addr_signal("MCAUSE (0x342, near MEPC 0x341)", CSR_MCAUSE, 0);
    check_no_flush_addr_signal("MIP (0x344, near MTVAL 0x343)",   CSR_MIP,    0);
    // Arbitrary addresses
    check_no_flush_addr_signal("Arbitrary 0x000", 12'h000, 0);
    check_no_flush_addr_signal("Arbitrary 0xFFF", 12'hFFF, 0);

    // ============================================================
    // CATEGORY 7: Immediate-form CSR instructions (CSRRWI/CSRRSI/CSRRCI)
    // Verify flush works with immediate-form CSR instructions too
    // ============================================================
    $display("\n--- Category 7: Immediate-form CSR instructions ---");

    // CSRRWI (funct3=101) - should flush for flush-required CSRs
    check_flush_imm("CSRRWI MSTATUS",  CSR_MSTATUS,  CSR_OP_WRITE, 5'd3,  1);
    check_flush_imm("CSRRWI PMPCFG0",  CSR_PMPCFG0,  CSR_OP_WRITE, 5'd15, 1);
    check_flush_imm("CSRRWI PMPADDR0", CSR_PMPADDR0, CSR_OP_WRITE, 5'd7,  1);
    check_flush_imm("CSRRWI MIE",      CSR_MIE,      CSR_OP_WRITE, 5'd1,  1);

    // CSRRSI (funct3=110) - should flush for flush-required CSRs
    check_flush_imm("CSRRSI MSTATUS",  CSR_MSTATUS,  CSR_OP_SET, 5'd8,  1);
    check_flush_imm("CSRRSI PMPCFG0",  CSR_PMPCFG0,  CSR_OP_SET, 5'd4,  1);
    check_flush_imm("CSRRSI PMPADDR0", CSR_PMPADDR0, CSR_OP_SET, 5'd31, 1);

    // CSRRCI (funct3=111) - the critical bug case with immediates
    check_flush_imm("CSRRCI PMPCFG0",  CSR_PMPCFG0,  CSR_OP_CLEAR, 5'd15, 1);
    check_flush_imm("CSRRCI PMPCFG1",  CSR_PMPCFG1,  CSR_OP_CLEAR, 5'd1,  1);
    check_flush_imm("CSRRCI PMPCFG2",  CSR_PMPCFG2,  CSR_OP_CLEAR, 5'd31, 1);
    check_flush_imm("CSRRCI PMPCFG3",  CSR_PMPCFG3,  CSR_OP_CLEAR, 5'd7,  1);
    check_flush_imm("CSRRCI PMPADDR0", CSR_PMPADDR0, CSR_OP_CLEAR, 5'd1,  1);
    check_flush_imm("CSRRCI PMPADDR8", CSR_PMPADDR8, CSR_OP_CLEAR, 5'd15, 1);
    check_flush_imm("CSRRCI PMPADDR15",CSR_PMPADDR15,CSR_OP_CLEAR, 5'd31, 1);
    check_flush_imm("CSRRCI MSTATUS",  CSR_MSTATUS,  CSR_OP_CLEAR, 5'd8,  1);
    check_flush_imm("CSRRCI MIE",      CSR_MIE,      CSR_OP_CLEAR, 5'd4,  1);
    check_flush_imm("CSRRCI MSECCFG",  CSR_MSECCFG,  CSR_OP_CLEAR, 5'd2,  1);
    check_flush_imm("CSRRCI DCSR",     CSR_DCSR,     CSR_OP_CLEAR, 5'd1,  1);

    // Immediate-form to no-flush CSRs - should NOT flush
    check_flush_imm("CSRRWI MSCRATCH", CSR_MSCRATCH, CSR_OP_WRITE, 5'd5,  0);
    check_flush_imm("CSRRSI MSCRATCH", CSR_MSCRATCH, CSR_OP_SET,   5'd1,  0);
    check_flush_imm("CSRRCI MSCRATCH", CSR_MSCRATCH, CSR_OP_CLEAR, 5'd3,  0);
    check_flush_imm("CSRRWI MEPC",     CSR_MEPC,     CSR_OP_WRITE, 5'd10, 0);
    check_flush_imm("CSRRSI MEPC",     CSR_MEPC,     CSR_OP_SET,   5'd2,  0);
    check_flush_imm("CSRRCI MEPC",     CSR_MEPC,     CSR_OP_CLEAR, 5'd1,  0);

    // Immediate-form with edge-case immediate values (0 and max)
    check_flush_imm("CSRRWI MSTATUS imm=0",  CSR_MSTATUS, CSR_OP_WRITE, 5'd0,  1);
    check_flush_imm("CSRRWI MSTATUS imm=31", CSR_MSTATUS, CSR_OP_WRITE, 5'd31, 1);
    check_flush_imm("CSRRCI PMPCFG0 imm=0",  CSR_PMPCFG0, CSR_OP_CLEAR, 5'd0,  1);
    check_flush_imm("CSRRCI PMPCFG0 imm=31", CSR_PMPCFG0, CSR_OP_CLEAR, 5'd31, 1);

    // ============================================================
    // CATEGORY 8: Arbitrary / non-standard CSR addresses
    // Verify flush behavior for addresses outside the known CSR set
    // (the fix flushes on ALL modifications except MSCRATCH/MEPC)
    // ============================================================
    $display("\n--- Category 8: Arbitrary CSR addresses ---");

    check_flush("Arbitrary 0x000 WRITE", 12'h000, CSR_OP_WRITE, 1);
    check_flush("Arbitrary 0x000 SET",   12'h000, CSR_OP_SET,   1);
    check_flush("Arbitrary 0x000 CLEAR", 12'h000, CSR_OP_CLEAR, 1);
    check_flush("Arbitrary 0xFFF WRITE", 12'hFFF, CSR_OP_WRITE, 1);
    check_flush("Arbitrary 0xFFF CLEAR", 12'hFFF, CSR_OP_CLEAR, 1);
    check_flush("Arbitrary 0xABC WRITE", 12'hABC, CSR_OP_WRITE, 1);
    check_flush("Arbitrary 0x123 SET",   12'h123, CSR_OP_SET,   1);
    // Near MSCRATCH (0x340) and MEPC (0x341) but not equal
    check_flush("Near-MSCRATCH 0x33F WRITE", 12'h33F, CSR_OP_WRITE, 1);
    check_flush("Near-MEPC 0x342 WRITE",     12'h342, CSR_OP_WRITE, 1); // this is MCAUSE
    check_flush("Near-MEPC 0x343 CLEAR",     12'h343, CSR_OP_CLEAR, 1); // this is MTVAL

    // READ for arbitrary addresses should never flush
    check_flush("Arbitrary 0x000 READ", 12'h000, CSR_OP_READ, 0);
    check_flush("Arbitrary 0xFFF READ", 12'hFFF, CSR_OP_READ, 0);
    check_flush("Arbitrary 0xABC READ", 12'hABC, CSR_OP_READ, 0);

    // ============================================================
    // CATEGORY 9: Back-to-back CSR operations across clock edges
    // Verify flush signal responds correctly to rapid instruction changes
    // ============================================================
    $display("\n--- Category 9: Back-to-back CSR operations across clock edges ---");

    begin
      logic flush_cycle1, flush_cycle2, flush_cycle3;

      // Cycle 1: PMP CLEAR (should flush)
      @(posedge clk);
      instr_rdata_i     = build_csr_instr(CSR_PMPCFG0, 3'b011, 5'd1, 5'd1);
      instr_rdata_alu_i = instr_rdata_i;
      instr_valid_i     = 1'b1;
      force dut.csr_op_en_o = 1'b1;
      force dut.csr_op_o    = CSR_OP_CLEAR;
      #1;
      flush_cycle1 = dut.csr_pipe_flush;

      // Cycle 2: MSCRATCH WRITE (should NOT flush)
      @(posedge clk);
      instr_rdata_i     = build_csr_instr(CSR_MSCRATCH, 3'b001, 5'd1, 5'd1);
      instr_rdata_alu_i = instr_rdata_i;
      force dut.csr_op_o    = CSR_OP_WRITE;
      #1;
      flush_cycle2 = dut.csr_pipe_flush;

      // Cycle 3: PMP CLEAR again (should flush)
      @(posedge clk);
      instr_rdata_i     = build_csr_instr(CSR_PMPADDR0, 3'b011, 5'd1, 5'd1);
      instr_rdata_alu_i = instr_rdata_i;
      force dut.csr_op_o    = CSR_OP_CLEAR;
      #1;
      flush_cycle3 = dut.csr_pipe_flush;

      release dut.csr_op_en_o;
      release dut.csr_op_o;
      instr_valid_i = 1'b0;

      test_count++;
      if (flush_cycle1 !== 1'b1) begin
        $display("FAIL [%0d]: Back-to-back cycle1 PMPCFG0 CLEAR | expected flush=1 got=%0b",
                 test_count, flush_cycle1);
        fail_count++;
      end else begin
        $display("PASS [%0d]: Back-to-back cycle1 PMPCFG0 CLEAR | flush=1", test_count);
        pass_count++;
      end

      test_count++;
      if (flush_cycle2 !== 1'b0) begin
        $display("FAIL [%0d]: Back-to-back cycle2 MSCRATCH WRITE | expected flush=0 got=%0b",
                 test_count, flush_cycle2);
        fail_count++;
      end else begin
        $display("PASS [%0d]: Back-to-back cycle2 MSCRATCH WRITE | flush=0", test_count);
        pass_count++;
      end

      test_count++;
      if (flush_cycle3 !== 1'b1) begin
        $display("FAIL [%0d]: Back-to-back cycle3 PMPADDR0 CLEAR | expected flush=1 got=%0b",
                 test_count, flush_cycle3);
        fail_count++;
      end else begin
        $display("PASS [%0d]: Back-to-back cycle3 PMPADDR0 CLEAR | flush=1", test_count);
        pass_count++;
      end
      #1;
    end

    // ============================================================
    // CATEGORY 10: Transition tests - flush signal deasserts correctly
    // when switching from flush-required to non-flush CSR
    // ============================================================
    $display("\n--- Category 10: Flush signal transition tests ---");

    begin
      logic flush_before, flush_after;

      // Start with a flush-requiring CSR
      instr_rdata_i     = build_csr_instr(CSR_PMPCFG0, 3'b011, 5'd1, 5'd1);
      instr_rdata_alu_i = instr_rdata_i;
      instr_valid_i     = 1'b1;
      force dut.csr_op_en_o = 1'b1;
      force dut.csr_op_o    = CSR_OP_CLEAR;
      #1;
      flush_before = dut.csr_pipe_flush;

      // Switch to MSCRATCH (no-flush) without deasserting valid
      instr_rdata_i     = build_csr_instr(CSR_MSCRATCH, 3'b001, 5'd1, 5'd1);
      instr_rdata_alu_i = instr_rdata_i;
      force dut.csr_op_o    = CSR_OP_WRITE;
      #1;
      flush_after = dut.csr_pipe_flush;

      release dut.csr_op_en_o;
      release dut.csr_op_o;
      instr_valid_i = 1'b0;

      test_count++;
      if (flush_before !== 1'b1 || flush_after !== 1'b0) begin
        $display("FAIL [%0d]: Transition PMPCFG0->MSCRATCH | flush: before=%0b(exp=1) after=%0b(exp=0)",
                 test_count, flush_before, flush_after);
        fail_count++;
      end else begin
        $display("PASS [%0d]: Transition PMPCFG0->MSCRATCH | flush: 1->0", test_count);
        pass_count++;
      end
      #1;
    end

    begin
      logic flush_before, flush_after;

      // Start with no-flush CSR
      instr_rdata_i     = build_csr_instr(CSR_MEPC, 3'b001, 5'd1, 5'd1);
      instr_rdata_alu_i = instr_rdata_i;
      instr_valid_i     = 1'b1;
      force dut.csr_op_en_o = 1'b1;
      force dut.csr_op_o    = CSR_OP_WRITE;
      #1;
      flush_before = dut.csr_pipe_flush;

      // Switch to flush-requiring PMPADDR CLEAR
      instr_rdata_i     = build_csr_instr(CSR_PMPADDR0, 3'b011, 5'd1, 5'd1);
      instr_rdata_alu_i = instr_rdata_i;
      force dut.csr_op_o    = CSR_OP_CLEAR;
      #1;
      flush_after = dut.csr_pipe_flush;

      release dut.csr_op_en_o;
      release dut.csr_op_o;
      instr_valid_i = 1'b0;

      test_count++;
      if (flush_before !== 1'b0 || flush_after !== 1'b1) begin
        $display("FAIL [%0d]: Transition MEPC->PMPADDR0 | flush: before=%0b(exp=0) after=%0b(exp=1)",
                 test_count, flush_before, flush_after);
        fail_count++;
      end else begin
        $display("PASS [%0d]: Transition MEPC->PMPADDR0 | flush: 0->1", test_count);
        pass_count++;
      end
      #1;
    end

    // ============================================================
    // CATEGORY 11: Verify csr_op_en_o toggling effect on flush
    // Flush should immediately respond to csr_op_en_o changes
    // ============================================================
    $display("\n--- Category 11: csr_op_en_o toggling effect ---");

    begin
      logic flush_enabled, flush_disabled;

      instr_rdata_i     = build_csr_instr(CSR_PMPADDR0, 3'b011, 5'd1, 5'd1);
      instr_rdata_alu_i = instr_rdata_i;
      instr_valid_i     = 1'b1;
      force dut.csr_op_o = CSR_OP_CLEAR;

      // Enable -> should flush
      force dut.csr_op_en_o = 1'b1;
      #1;
      flush_enabled = dut.csr_pipe_flush;

      // Disable -> should not flush
      force dut.csr_op_en_o = 1'b0;
      #1;
      flush_disabled = dut.csr_pipe_flush;

      release dut.csr_op_en_o;
      release dut.csr_op_o;
      instr_valid_i = 1'b0;

      test_count++;
      if (flush_enabled !== 1'b1 || flush_disabled !== 1'b0) begin
        $display("FAIL [%0d]: op_en toggle | en=%0b(exp=1) dis=%0b(exp=0)",
                 test_count, flush_enabled, flush_disabled);
        fail_count++;
      end else begin
        $display("PASS [%0d]: op_en toggle | flush: en=1 dis=0", test_count);
        pass_count++;
      end
      #1;
    end

    // ============================================================
    // CATEGORY 12: CSR op type toggling with same address
    // Switch between READ/WRITE/SET/CLEAR on same CSR and verify
    // ============================================================
    $display("\n--- Category 12: CSR op type cycling on same address ---");

    begin
      logic flush_read, flush_write, flush_set, flush_clear;

      instr_rdata_i     = build_csr_instr(CSR_PMPADDR5, 3'b001, 5'd1, 5'd1);
      instr_rdata_alu_i = instr_rdata_i;
      instr_valid_i     = 1'b1;
      force dut.csr_op_en_o = 1'b1;

      force dut.csr_op_o = CSR_OP_READ;
      #1;
      flush_read = dut.csr_pipe_flush;

      force dut.csr_op_o = CSR_OP_WRITE;
      #1;
      flush_write = dut.csr_pipe_flush;

      force dut.csr_op_o = CSR_OP_SET;
      #1;
      flush_set = dut.csr_pipe_flush;

      force dut.csr_op_o = CSR_OP_CLEAR;
      #1;
      flush_clear = dut.csr_pipe_flush;

      release dut.csr_op_en_o;
      release dut.csr_op_o;
      instr_valid_i = 1'b0;

      test_count++;
      if (flush_read !== 1'b0 || flush_write !== 1'b1 ||
          flush_set !== 1'b1 || flush_clear !== 1'b1) begin
        $display("FAIL [%0d]: PMPADDR5 op cycle | R=%0b(exp=0) W=%0b(exp=1) S=%0b(exp=1) C=%0b(exp=1)",
                 test_count, flush_read, flush_write, flush_set, flush_clear);
        fail_count++;
      end else begin
        $display("PASS [%0d]: PMPADDR5 op cycle | R=0 W=1 S=1 C=1", test_count);
        pass_count++;
      end
      #1;
    end

    // Same test for a no-flush CSR (MSCRATCH)
    begin
      logic flush_read, flush_write, flush_set, flush_clear;

      instr_rdata_i     = build_csr_instr(CSR_MSCRATCH, 3'b001, 5'd1, 5'd1);
      instr_rdata_alu_i = instr_rdata_i;
      instr_valid_i     = 1'b1;
      force dut.csr_op_en_o = 1'b1;

      force dut.csr_op_o = CSR_OP_READ;
      #1;
      flush_read = dut.csr_pipe_flush;

      force dut.csr_op_o = CSR_OP_WRITE;
      #1;
      flush_write = dut.csr_pipe_flush;

      force dut.csr_op_o = CSR_OP_SET;
      #1;
      flush_set = dut.csr_pipe_flush;

      force dut.csr_op_o = CSR_OP_CLEAR;
      #1;
      flush_clear = dut.csr_pipe_flush;

      release dut.csr_op_en_o;
      release dut.csr_op_o;
      instr_valid_i = 1'b0;

      test_count++;
      if (flush_read !== 1'b0 || flush_write !== 1'b0 ||
          flush_set !== 1'b0 || flush_clear !== 1'b0) begin
        $display("FAIL [%0d]: MSCRATCH op cycle | R=%0b(exp=0) W=%0b(exp=0) S=%0b(exp=0) C=%0b(exp=0)",
                 test_count, flush_read, flush_write, flush_set, flush_clear);
        fail_count++;
      end else begin
        $display("PASS [%0d]: MSCRATCH op cycle | all=0 (no flush for any op)", test_count);
        pass_count++;
      end
      #1;
    end

    // ============================================================
    // CATEGORY 13: Sweep PMP address space with all three operations
    // The pre-patch code used instr_rdata_i[31:25] == 7'h1D to match
    // PMP registers. Verify all 16 PMPADDR + 4 PMPCFG with SET
    // (which worked pre-patch) and CLEAR (which was the bug).
    // ============================================================
    $display("\n--- Category 13: Full PMP sweep with SET and CLEAR ---");

    // PMPCFG 0-3 with SET
    check_flush("PMPCFG0 SET sweep", CSR_PMPCFG0, CSR_OP_SET, 1);
    check_flush("PMPCFG1 SET sweep", CSR_PMPCFG1, CSR_OP_SET, 1);
    check_flush("PMPCFG2 SET sweep", CSR_PMPCFG2, CSR_OP_SET, 1);
    check_flush("PMPCFG3 SET sweep", CSR_PMPCFG3, CSR_OP_SET, 1);

    // PMPADDR 0-15 with SET (all should flush)
    check_flush("PMPADDR0 SET sweep",  CSR_PMPADDR0,  CSR_OP_SET, 1);
    check_flush("PMPADDR1 SET sweep",  CSR_PMPADDR1,  CSR_OP_SET, 1);
    check_flush("PMPADDR2 SET sweep",  CSR_PMPADDR2,  CSR_OP_SET, 1);
    check_flush("PMPADDR3 SET sweep",  CSR_PMPADDR3,  CSR_OP_SET, 1);
    check_flush("PMPADDR4 SET sweep",  CSR_PMPADDR4,  CSR_OP_SET, 1);
    check_flush("PMPADDR5 SET sweep",  CSR_PMPADDR5,  CSR_OP_SET, 1);
    check_flush("PMPADDR6 SET sweep",  CSR_PMPADDR6,  CSR_OP_SET, 1);
    check_flush("PMPADDR7 SET sweep",  CSR_PMPADDR7,  CSR_OP_SET, 1);
    check_flush("PMPADDR8 SET sweep",  CSR_PMPADDR8,  CSR_OP_SET, 1);
    check_flush("PMPADDR9 SET sweep",  CSR_PMPADDR9,  CSR_OP_SET, 1);
    check_flush("PMPADDR10 SET sweep", CSR_PMPADDR10, CSR_OP_SET, 1);
    check_flush("PMPADDR11 SET sweep", CSR_PMPADDR11, CSR_OP_SET, 1);
    check_flush("PMPADDR12 SET sweep", CSR_PMPADDR12, CSR_OP_SET, 1);
    check_flush("PMPADDR13 SET sweep", CSR_PMPADDR13, CSR_OP_SET, 1);
    check_flush("PMPADDR14 SET sweep", CSR_PMPADDR14, CSR_OP_SET, 1);
    check_flush("PMPADDR15 SET sweep", CSR_PMPADDR15, CSR_OP_SET, 1);

    // PMPADDR 0-15 with WRITE (all should flush)
    check_flush("PMPADDR0 WRITE sweep",  CSR_PMPADDR0,  CSR_OP_WRITE, 1);
    check_flush("PMPADDR1 WRITE sweep",  CSR_PMPADDR1,  CSR_OP_WRITE, 1);
    check_flush("PMPADDR2 WRITE sweep",  CSR_PMPADDR2,  CSR_OP_WRITE, 1);
    check_flush("PMPADDR3 WRITE sweep",  CSR_PMPADDR3,  CSR_OP_WRITE, 1);
    check_flush("PMPADDR4 WRITE sweep",  CSR_PMPADDR4,  CSR_OP_WRITE, 1);
    check_flush("PMPADDR5 WRITE sweep",  CSR_PMPADDR5,  CSR_OP_WRITE, 1);
    check_flush("PMPADDR6 WRITE sweep",  CSR_PMPADDR6,  CSR_OP_WRITE, 1);
    check_flush("PMPADDR7 WRITE sweep",  CSR_PMPADDR7,  CSR_OP_WRITE, 1);
    check_flush("PMPADDR8 WRITE sweep",  CSR_PMPADDR8,  CSR_OP_WRITE, 1);
    check_flush("PMPADDR9 WRITE sweep",  CSR_PMPADDR9,  CSR_OP_WRITE, 1);
    check_flush("PMPADDR10 WRITE sweep", CSR_PMPADDR10, CSR_OP_WRITE, 1);
    check_flush("PMPADDR11 WRITE sweep", CSR_PMPADDR11, CSR_OP_WRITE, 1);
    check_flush("PMPADDR12 WRITE sweep", CSR_PMPADDR12, CSR_OP_WRITE, 1);
    check_flush("PMPADDR13 WRITE sweep", CSR_PMPADDR13, CSR_OP_WRITE, 1);
    check_flush("PMPADDR14 WRITE sweep", CSR_PMPADDR14, CSR_OP_WRITE, 1);
    check_flush("PMPADDR15 WRITE sweep", CSR_PMPADDR15, CSR_OP_WRITE, 1);

    // ============================================================
    // CATEGORY 14: Different rd/rs1 register encodings
    // Verify that rd and rs1 fields don't affect flush logic
    // ============================================================
    $display("\n--- Category 14: rd/rs1 field independence ---");

    begin
      logic actual_flush;
      int rd_vals [5] = '{0, 1, 15, 30, 31};

      for (int i = 0; i < 5; i++) begin
        test_count++;
        instr_rdata_i     = build_csr_instr(CSR_PMPCFG0, 3'b011, 5'd1, rd_vals[i][4:0]);
        instr_rdata_alu_i = instr_rdata_i;
        instr_valid_i     = 1'b1;
        force dut.csr_op_en_o = 1'b1;
        force dut.csr_op_o    = CSR_OP_CLEAR;
        #1;
        actual_flush = dut.csr_pipe_flush;
        if (actual_flush !== 1'b1) begin
          $display("FAIL [%0d]: PMPCFG0 CLEAR rd=x%0d | expected flush=1 got=%0b",
                   test_count, rd_vals[i], actual_flush);
          fail_count++;
        end else begin
          $display("PASS [%0d]: PMPCFG0 CLEAR rd=x%0d | flush=1",
                   test_count, rd_vals[i]);
          pass_count++;
        end
        release dut.csr_op_en_o;
        release dut.csr_op_o;
        instr_valid_i = 1'b0;
        #1;
      end

      for (int i = 0; i < 5; i++) begin
        test_count++;
        instr_rdata_i     = build_csr_instr(CSR_PMPADDR0, 3'b011, rd_vals[i][4:0], 5'd1);
        instr_rdata_alu_i = instr_rdata_i;
        instr_valid_i     = 1'b1;
        force dut.csr_op_en_o = 1'b1;
        force dut.csr_op_o    = CSR_OP_CLEAR;
        #1;
        actual_flush = dut.csr_pipe_flush;
        if (actual_flush !== 1'b1) begin
          $display("FAIL [%0d]: PMPADDR0 CLEAR rs1=x%0d | expected flush=1 got=%0b",
                   test_count, rd_vals[i], actual_flush);
          fail_count++;
        end else begin
          $display("PASS [%0d]: PMPADDR0 CLEAR rs1=x%0d | flush=1",
                   test_count, rd_vals[i]);
          pass_count++;
        end
        release dut.csr_op_en_o;
        release dut.csr_op_o;
        instr_valid_i = 1'b0;
        #1;
      end
    end

    // ============================================================
    // CATEGORY 15: SCONTEXT CSR (different address region)
    // Verify CSRs in different address ranges also flush
    // ============================================================
    $display("\n--- Category 15: Additional CSR address regions ---");

    check_flush("SCONTEXT WRITE",   CSR_SCONTEXT,  CSR_OP_WRITE, 1);
    check_flush("SCONTEXT SET",     CSR_SCONTEXT,  CSR_OP_SET,   1);
    check_flush("SCONTEXT CLEAR",   CSR_SCONTEXT,  CSR_OP_CLEAR, 1);
    check_flush("MSCONTEXT WRITE",  CSR_MSCONTEXT, CSR_OP_WRITE, 1);
    check_flush("MCONFIGPTR WRITE", CSR_MCONFIGPTR, CSR_OP_WRITE, 1);

    // ============================================================
    // Summary
    // ============================================================
    $display("\n==========================================================");
    $display("  Test Summary: %0d total, %0d passed, %0d failed",
             test_count, pass_count, fail_count);
    $display("==========================================================\n");

    $display("Functional Coverage: %.1f%%", cg_inst.get_coverage());
    if (fail_count > 0) begin
      $display("FAIL: %0d test(s) failed!", fail_count);
      $finish(1);
    end else begin
      $display("All %0d tests passed!", pass_count);
      $finish(0);
    end
  end

  // -------------------------
  // Timeout watchdog
  // -------------------------
  initial begin
    #200000;
    $display("ERROR: Simulation timeout!");
    $finish(2);
  end

  // -------------------------
  // VCD dump
  // -------------------------
  initial begin
    $dumpfile("tb_ibex_id_stage_csr_flush_patch.vcd");
    $dumpvars(0);
  end

endmodule

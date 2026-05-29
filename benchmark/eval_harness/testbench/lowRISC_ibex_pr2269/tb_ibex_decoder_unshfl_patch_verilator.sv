module tb_ibex_decoder_unshfl_patch;

  import ibex_pkg::*;

  localparam logic [6:0] OPCODE_OP_IMM = 7'b0010011;
  localparam logic [2:0] FUNCT3_SHFLI  = 3'b101;
  localparam logic [4:0] FUNCT5_UNSHFL = 5'b0_0001;

  // Clk/Reset
  logic clk_i = 0;
  logic rst_ni = 0;
  always #5 clk_i = ~clk_i;

  // to/from controller
  logic illegal_insn_o;
  logic ebrk_insn_o;
  logic mret_insn_o;
  logic dret_insn_o;
  logic ecall_insn_o;
  logic wfi_insn_o;
  logic jump_set_o;
  logic branch_taken_i;
  logic icache_inval_o;

  // IF/ID inputs
  logic instr_first_cycle_i;
  logic [31:0] instr_rdata_i;
  logic [31:0] instr_rdata_alu_i;
  logic illegal_c_insn_i;

  // immediates
  imm_a_sel_e imm_a_mux_sel_o;
  imm_b_sel_e imm_b_mux_sel_o;
  op_a_sel_e  bt_a_mux_sel_o;
  imm_b_sel_e bt_b_mux_sel_o;
  logic [31:0] imm_i_type_o;
  logic [31:0] imm_s_type_o;
  logic [31:0] imm_b_type_o;
  logic [31:0] imm_u_type_o;
  logic [31:0] imm_j_type_o;
  logic [31:0] zimm_rs1_type_o;

  // register file
  rf_wd_sel_e rf_wdata_sel_o;
  logic       rf_we_o;
  logic [4:0] rf_raddr_a_o;
  logic [4:0] rf_raddr_b_o;
  logic [4:0] rf_waddr_o;
  logic       rf_ren_a_o;
  logic       rf_ren_b_o;

  // ALU
  alu_op_e    alu_operator_o;
  op_a_sel_e  alu_op_a_mux_sel_o;
  op_b_sel_e  alu_op_b_mux_sel_o;
  logic       alu_multicycle_o;

  // Mult/Div
  logic       mult_en_o;
  logic       div_en_o;
  logic       mult_sel_o;
  logic       div_sel_o;
  md_op_e     multdiv_operator_o;
  logic [1:0] multdiv_signed_mode_o;

  // CSR
  logic        csr_access_o;
  csr_op_e     csr_op_o;
  csr_num_e    csr_addr_o;

  // LSU
  logic        data_req_o;
  logic        data_we_o;
  logic [1:0]  data_type_o;
  logic        data_sign_extension_o;

  // jump/branch
  logic        jump_in_dec_o;
  logic        branch_in_dec_o;
  logic [31:0] instr_word;

  ibex_decoder #(
    .RV32B(ibex_pkg::RV32BFull)
  ) dut (.*);

  // -----------------------
  // Stimulus
  // -----------------------
  initial begin
    $display("=== Ibex decoder unshfl dead-code regression ===");

    branch_taken_i      = 1'b0;
    instr_first_cycle_i = 1'b1;
    instr_rdata_i       = '0;
    instr_rdata_alu_i   = '0;
    illegal_c_insn_i    = 1'b0;

    repeat (2) @(posedge clk_i);
    rst_ni = 1'b1;

    // Build an UNZIP/UNSHFL immediate instruction and leave instr[26] as X to
    // reproduce the dead-code issue that used to mark it illegal.
    instr_word = '0;
    instr_word[6:0]   = OPCODE_OP_IMM;
    instr_word[11:7]  = 5'd3;
    instr_word[14:12] = FUNCT3_SHFLI;
    instr_word[19:15] = 5'd1;
    instr_word[24:20] = 5'd0;
    instr_word[31:27] = FUNCT5_UNSHFL;
    instr_word[26]    = 1'bx;

    instr_rdata_i     = instr_word;
    instr_rdata_alu_i = instr_word;

    #1;
    if (illegal_insn_o === 1'b0) begin
      $display("PASS: UNZIP/UNSHFL remains legal even when instr[26] is X.");
    end else begin
      $fatal(1, "FAIL: UNZIP/UNSHFL treated as illegal when instr[26] is X (illegal_insn_o=%b).",
               illegal_insn_o);
    end
    @(posedge clk_i);

    // ---- Additional instructions to hit coverage bins ----

    // Test UNSHFL with bit26=0 (normal valid encoding)
    instr_word = '0;
    instr_word[6:0]   = OPCODE_OP_IMM;
    instr_word[11:7]  = 5'd3;
    instr_word[14:12] = FUNCT3_SHFLI;
    instr_word[19:15] = 5'd1;
    instr_word[24:20] = 5'd0;
    instr_word[31:27] = FUNCT5_UNSHFL;
    instr_word[26]    = 1'b0;
    instr_rdata_i     = instr_word;
    instr_rdata_alu_i = instr_word;
    #1;
    @(posedge clk_i);

    // Test UNSHFL with bit26=1
    instr_word[26]    = 1'b1;
    instr_rdata_i     = instr_word;
    instr_rdata_alu_i = instr_word;
    #1;
    @(posedge clk_i);

    // Test a different opcode (e.g. LOAD: 7'b0000011) -> hits cp_opcode.others
    instr_rdata_i     = 32'h00002003; // lw x0, 0(x0)
    instr_rdata_alu_i = 32'h00002003;
    #1;
    @(posedge clk_i);

    // Test an illegal instruction -> hits cp_illegal.illegal
    instr_rdata_i     = 32'hFFFF_FFFF;
    instr_rdata_alu_i = 32'hFFFF_FFFF;
    #1;
    @(posedge clk_i);

    // Test OP_IMM with different funct3 (e.g. ADDI: funct3=000) -> hits cp_funct3.others
    instr_rdata_i     = 32'h00100093; // addi x1, x0, 1
    instr_rdata_alu_i = 32'h00100093;
    #1;
    @(posedge clk_i);

    // Test OP_IMM with shfli funct3 but different funct5 (e.g. SRI: funct5=01000)
    instr_word = '0;
    instr_word[6:0]   = OPCODE_OP_IMM;
    instr_word[11:7]  = 5'd3;
    instr_word[14:12] = FUNCT3_SHFLI;
    instr_word[19:15] = 5'd1;
    instr_word[24:20] = 5'd0;
    instr_word[31:27] = 5'b01000; // different funct5
    instr_word[26]    = 1'b0;
    instr_rdata_i     = instr_word;
    instr_rdata_alu_i = instr_word;
    #1;
    @(posedge clk_i);

    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end


  initial begin
    $dumpfile("tb_ibex_decoder_unshfl_patch.vcd");
    $dumpvars(0);
  end

  // ---------------------------------------------------------------
  // Patch-focused functional coverage
  // ---------------------------------------------------------------
  // Patch: Removed dead-code check on instr[26] for unshfl opcode.
  // Previously, when instr[26]!=0 it was marked illegal, but the
  // enclosing else already guaranteed instr[26]==0.

  // [verilator-strip cg] covergroup cg_patch @(posedge clk_i);
// [verilator-strip cg]     cp_illegal: coverpoint illegal_insn_o {
// [verilator-strip cg]       bins legal   = {1'b0};
// [verilator-strip cg]       bins illegal = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_opcode: coverpoint instr_rdata_i[6:0] {
// [verilator-strip cg]       bins op_imm = {OPCODE_OP_IMM};
// [verilator-strip cg]       bins others = default;
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_funct3: coverpoint instr_rdata_i[14:12] {
// [verilator-strip cg]       bins shfli  = {FUNCT3_SHFLI};
// [verilator-strip cg]       bins others = default;
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_funct5: coverpoint instr_rdata_i[31:27] {
// [verilator-strip cg]       bins unshfl = {FUNCT5_UNSHFL};
// [verilator-strip cg]       bins others = default;
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_bit26: coverpoint instr_rdata_i[26] {
// [verilator-strip cg]       bins zero = {1'b0};
// [verilator-strip cg]       bins one  = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cross: unshfl instruction with instr[26] value and legality
// [verilator-strip cg]     cx_unshfl_legal: cross cp_opcode, cp_funct3, cp_funct5, cp_illegal {
// [verilator-strip cg]       // Non-OP_IMM opcodes don't have meaningful funct3/funct5 for this cross
// [verilator-strip cg]       ignore_bins ig_other_opcode = binsof(cp_opcode.others);
// [verilator-strip cg]       // UNSHFL with shfli funct3 is always legal (the fix ensures this)
// [verilator-strip cg]       ignore_bins ig_unshfl_illegal = binsof(cp_funct5.unshfl) && binsof(cp_funct3.shfli) && binsof(cp_illegal.illegal);
// [verilator-strip cg]     }
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_patch cg_inst = new();

endmodule

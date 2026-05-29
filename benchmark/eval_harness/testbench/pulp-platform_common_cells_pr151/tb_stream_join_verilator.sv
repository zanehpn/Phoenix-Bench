`timescale 1ns/1ps

module tb_stream_join;

  localparam int unsigned N_INP = 4;

  logic [N_INP-1:0] inp_valid_i;
  logic [N_INP-1:0] inp_ready_o_golden;
  logic [N_INP-1:0] inp_ready_o_buggy;

  logic [N_INP-1:0] sel_i;

  logic oup_valid_o_golden;
  logic oup_valid_o_buggy;

  logic oup_ready_i;

  // ---- DUT: Golden ----
  stream_join_dynamic_old #(
    .N_INP(N_INP)
  ) u_golden (
    .inp_valid_i (inp_valid_i),
    .inp_ready_o (inp_ready_o_golden),
    .sel_i       (sel_i),
    .oup_valid_o (oup_valid_o_golden),
    .oup_ready_i (oup_ready_i)
  );

  // ---- DUT: Buggy ----
  stream_join_dynamic #(
    .N_INP(N_INP)
  ) u_buggy (
    .inp_valid_i (inp_valid_i),
    .inp_ready_o (inp_ready_o_buggy),
    .sel_i       (sel_i),
    .oup_valid_o (oup_valid_o_buggy),
    .oup_ready_i (oup_ready_i)
  );

  // ---- Patch-related functional coverage ----
  // [verilator-strip cg] covergroup cg_inst @(inp_valid_i, sel_i, oup_ready_i);
// [verilator-strip cg]     cp_sel: coverpoint sel_i {
// [verilator-strip cg]       bins all_zero  = {4'b0000};
// [verilator-strip cg]       bins all_one   = {4'b1111};
// [verilator-strip cg]       bins partial[] = {[4'b0001:4'b1110]};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_inp_valid: coverpoint inp_valid_i {
// [verilator-strip cg]       bins all_zero  = {4'b0000};
// [verilator-strip cg]       bins all_one   = {4'b1111};
// [verilator-strip cg]       bins partial[] = {[4'b0001:4'b1110]};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_oup_ready: coverpoint oup_ready_i {
// [verilator-strip cg]       bins ready   = {1'b1};
// [verilator-strip cg]       bins unready = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     cross_sel_valid: cross cp_sel, cp_inp_valid;
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_inst cg = new();

  // 期望的 golden 输出函数（和 golden RTL 等价）
  function automatic logic exp_golden_valid(logic [N_INP-1:0] v, logic [N_INP-1:0] s);
    exp_golden_valid = (&(v | ~s)) && (|s);
  endfunction

  task automatic check(string name, logic got, logic exp);
    if (got !== exp) begin
      $display("[%0t] %s FAIL: got=%0b exp=%0b", $time, name, got, exp);
      $fatal(1);
    end else begin
      $display("[%0t] %s PASS: got=%0b", $time, name, got);
    end
  endtask

  initial begin
    // 默认
    oup_ready_i  = 1'b1;
    inp_valid_i  = '0;
    sel_i        = '0;
    #1;

    // Case 0: sel全0 -> golden必须不valid
    inp_valid_i = 4'b1111;
    sel_i       = 4'b0000;
    #1;
    check("golden sel=0 => oup_valid", oup_valid_o_golden, exp_golden_valid(inp_valid_i, sel_i));
    // buggy这里没有sel概念，不做“sel=0应当无valid”的检查

    // Case 1: 关键区分用例
    // 选中[3:1]有效，bit0未选中且为0
    // golden: 期望 valid=1
    // buggy : &inp_valid_i = 0 -> valid=0 (应当FAIL，如果你拿golden期望去对它)
    inp_valid_i = 4'b1110;
    sel_i       = 4'b1110;
    #1;

    // Golden 应该 PASS
    check("golden partial-select => oup_valid", oup_valid_o_golden, 1'b1);

    // Buggy 用 golden 的“正确期望”来比对，它必然 FAIL
    // （如果你想在同一次仿真中看到它fail，就保留这一行）
    check("buggy vs golden expectation => oup_valid", oup_valid_o_buggy, 1'b1);

    // Exhaustive sweep to achieve 100% functional coverage
    for (int s = 0; s < 16; s++) begin
      for (int v = 0; v < 16; v++) begin
        for (int rdy = 0; rdy < 2; rdy++) begin
          sel_i       = s[3:0];
          inp_valid_i = v[3:0];
          oup_ready_i = rdy[0];
          #1;
        end
      end
    end

    $display("All checks done.");
    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end


  initial begin
    $dumpfile("tb_stream_join.vcd");
    $dumpvars(0);
  end

endmodule

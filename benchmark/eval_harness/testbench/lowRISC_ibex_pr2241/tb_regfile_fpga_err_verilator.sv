`timescale 1ns/1ps

// Testbench for lowRISC_ibex_pr2241
//
// Patch: Drive oh_raddr_a_err and oh_raddr_b_err to 1'b0 when
// RdataMuxCheck=0. Previously these were undriven, causing lint
// warnings and potential X propagation in err_o.

module tb_regfile_fpga_err;

  logic        clk;
  logic        rst_ni;
  logic        test_en_i;
  logic        dummy_instr_id_i;
  logic        dummy_instr_wb_i;

  logic [4:0]  raddr_a_i;
  logic [31:0] rdata_a_o;
  logic [4:0]  raddr_b_i;
  logic [31:0] rdata_b_o;
  logic [4:0]  waddr_a_i;
  logic [31:0] wdata_a_i;
  logic        we_a_i;
  logic        err_o;

  // DUT with RdataMuxCheck=0 (the patched path)
  ibex_register_file_fpga #(
    .RV32E(0),
    .DataWidth(32),
    .DummyInstructions(0),
    .WrenCheck(0),
    .RdataMuxCheck(0),
    .WordZeroVal('0)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_ni),
    .test_en_i(test_en_i),
    .dummy_instr_id_i(dummy_instr_id_i),
    .dummy_instr_wb_i(dummy_instr_wb_i),
    .raddr_a_i(raddr_a_i),
    .rdata_a_o(rdata_a_o),
    .raddr_b_i(raddr_b_i),
    .rdata_b_o(rdata_b_o),
    .waddr_a_i(waddr_a_i),
    .wdata_a_i(wdata_a_i),
    .we_a_i(we_a_i),
    .err_o(err_o)
  );

  // Clock
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  integer fail = 0;

  initial begin
    $display("=== Register File FPGA err_o Drive Fix Test (PR #2241) ===");

    rst_ni = 0;
    test_en_i = 0;
    dummy_instr_id_i = 0;
    dummy_instr_wb_i = 0;
    raddr_a_i = 0;
    raddr_b_i = 0;
    waddr_a_i = 0;
    wdata_a_i = 0;
    we_a_i = 0;

    repeat (3) @(posedge clk);
    rst_ni = 1;

    // Test 1: err_o must NOT be X (the bug was undriven signals causing X)
    @(posedge clk);
    if (err_o === 1'bx) begin
      $fatal(1, "FAIL: err_o is X (undriven oh_raddr signals)");
      fail = 1;
    end else begin
      $display("PASS: err_o is driven (not X), value=%b", err_o);
    end

    // Test 2: err_o should be 0 since WrenCheck=0 and RdataMuxCheck=0
    if (err_o !== 1'b0) begin
      $fatal(1, "FAIL: err_o=%b, expected 0", err_o);
      fail = 1;
    end else begin
      $display("PASS: err_o=0 as expected");
    end

    // Test 3: Write to register 1, read back
    waddr_a_i = 5'd1;
    wdata_a_i = 32'hDEADBEEF;
    we_a_i = 1;
    @(posedge clk);
    we_a_i = 0;
    raddr_a_i = 5'd1;
    raddr_b_i = 5'd0;
    @(posedge clk);
    #1;

    if (rdata_a_o !== 32'hDEADBEEF) begin
      $fatal(1, "FAIL: Read back from reg1=%h, expected DEADBEEF", rdata_a_o);
      fail = 1;
    end else begin
      $display("PASS: Read back from reg1 correct");
    end

    // err_o should still be 0
    if (err_o !== 1'b0) begin
      $fatal(1, "FAIL: err_o=%b after operations", err_o);
      fail = 1;
    end

    // Test 4: Read from reg0 (should be zero)
    raddr_a_i = 5'd0;
    #1;
    if (rdata_a_o !== 32'h0) begin
      $fatal(1, "FAIL: reg0 read=%h, expected 0", rdata_a_o);
      fail = 1;
    end else begin
      $display("PASS: reg0 reads as zero");
    end

    // Test 5: Write multiple registers and read
    waddr_a_i = 5'd2; wdata_a_i = 32'hCAFEBABE; we_a_i = 1;
    @(posedge clk);
    waddr_a_i = 5'd3; wdata_a_i = 32'h12345678; we_a_i = 1;
    @(posedge clk);
    we_a_i = 0;
    raddr_a_i = 5'd2;
    raddr_b_i = 5'd3;
    @(posedge clk);
    #1;

    // err_o must remain 0 through all operations
    if (err_o !== 1'b0) begin
      $fatal(1, "FAIL: err_o non-zero after multi-reg operations");
      fail = 1;
    end

    repeat (3) @(posedge clk);

    if (fail == 0)
      $display("PASS: All tests passed.");
    else
      $fatal(1, "FAIL");

    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end

  // Safety timeout
  initial begin
    #50000;
    $fatal(1, "FAIL: Timeout");
  end

  // ---------------------------------------------------------------
  // Patch-focused functional coverage
  // ---------------------------------------------------------------
  // Patch: oh_raddr_a_err and oh_raddr_b_err driven to 0 when RdataMuxCheck=0

  // [verilator-strip cg] covergroup cg_patch @(posedge clk);
// [verilator-strip cg]     cp_err_o: coverpoint err_o {
// [verilator-strip cg]       bins zero = {1'b0};
// [verilator-strip cg]       ignore_bins one  = {1'b1};  // unreachable: RdataMuxCheck=0 and WrenCheck=0 => err_o always 0
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_we: coverpoint we_a_i {
// [verilator-strip cg]       bins no_write = {1'b0};
// [verilator-strip cg]       bins write    = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_raddr_a: coverpoint raddr_a_i {
// [verilator-strip cg]       bins zero    = {5'd0};
// [verilator-strip cg]       bins nonzero = {[5'd1:5'd31]};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_raddr_b: coverpoint raddr_b_i {
// [verilator-strip cg]       bins zero    = {5'd0};
// [verilator-strip cg]       bins nonzero = {[5'd1:5'd31]};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_waddr: coverpoint waddr_a_i {
// [verilator-strip cg]       bins zero    = {5'd0};
// [verilator-strip cg]       bins nonzero = {[5'd1:5'd31]};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cross: err_o should remain 0 regardless of read/write activity
// [verilator-strip cg]     cx_err_we: cross cp_err_o, cp_we;
// [verilator-strip cg]     cx_err_raddr: cross cp_err_o, cp_raddr_a;
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_patch cg_inst = new();

endmodule

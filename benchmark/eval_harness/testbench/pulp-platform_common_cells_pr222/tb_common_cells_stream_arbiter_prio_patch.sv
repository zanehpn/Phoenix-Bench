`timescale 1ns/1ps
// Signal-level F2P tb for pr222.
// Pre-patch: stream_arbiter_flushable (ARBITER="prio") instantiates rr_arb_tree
//   with LockIn=1 AND ExtPrio=1. rr_arb_tree has an initial-block assertion:
//     assert(!(LockIn && ExtPrio)) else $fatal(...);
//   which fires → sim exits non-zero.
// Post-patch: LockIn=0 → assertion passes → sim completes cleanly.
module tb_common_cells_stream_arbiter_prio_patch;
  localparam int unsigned N_INP  = 4;
  localparam int unsigned DATA_W = 8;

  logic clk, rst_n, flush;
  logic [N_INP-1:0][DATA_W-1:0] inp_data;
  logic [N_INP-1:0] inp_valid, inp_ready;
  logic [DATA_W-1:0] oup_data;
  logic oup_valid;
  logic oup_ready;

  stream_arbiter_flushable #(
    .DATA_T  (logic [DATA_W-1:0]),
    .N_INP   (N_INP),
    .ARBITER ("prio")
  ) dut (
    .clk_i      (clk),
    .rst_ni     (rst_n),
    .flush_i    (flush),
    .inp_data_i (inp_data),
    .inp_valid_i(inp_valid),
    .inp_ready_o(inp_ready),
    .oup_data_o (oup_data),
    .oup_valid_o(oup_valid),
    .oup_ready_i(oup_ready)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 0; flush = 0; oup_ready = 1;
    for (int i = 0; i < N_INP; i++) begin
      inp_data[i]  = i;
      inp_valid[i] = 0;
    end
    repeat (3) @(posedge clk);
    rst_n = 1;
    // Stimulate prio arbiter: multiple inputs active at once
    inp_valid = 4'b1111;
    repeat (4) @(posedge clk);
    inp_valid = 4'b0000;
    repeat (2) @(posedge clk);
    $display("PASS: stream_arbiter_flushable (prio) elaborates and runs without LockIn/ExtPrio conflict.");
    $finish;
  end
endmodule

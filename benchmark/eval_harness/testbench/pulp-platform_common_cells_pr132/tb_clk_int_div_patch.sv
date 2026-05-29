`timescale 1ns/1ps
// Signal-level F2P tb: instantiate clk_int_div (new module from patch).
// Buggy: module doesn't exist → build fails.
// Patched: module compiles and simulation runs.
module tb_clk_int_div_patch;
  localparam int unsigned DVW = 4;

  logic clk, rst_n;
  logic en, tm;
  logic [DVW-1:0] div;
  logic div_valid;
  logic div_ready;
  logic clk_o;
  logic cycle_seen;

  clk_int_div #(
    .DIV_VALUE_WIDTH (DVW),
    .DEFAULT_DIV_VALUE (2),
    .ENABLE_CLOCK_IN_RESET (1'b0)
  ) dut (
    .clk_i          (clk),
    .rst_ni         (rst_n),
    .en_i           (en),
    .test_mode_en_i (tm),
    .div_i          (div),
    .div_valid_i    (div_valid),
    .div_ready_o    (div_ready),
    .clk_o          (clk_o),
    .cycl_count_o   ()
  );

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 0; en = 0; tm = 0; div = 2; div_valid = 0; cycle_seen = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;
    en = 1;
    // Wait up to 200 cycles for clk_o to toggle
    for (int i = 0; i < 200; i++) begin
      @(posedge clk);
      if (clk_o) cycle_seen = 1;
    end
    if (!cycle_seen)
      $fatal(1, "FAIL: clk_int_div produced no output clock pulse.");
    $display("PASS: clk_int_div drives output clock.");
    $finish;
  end
endmodule

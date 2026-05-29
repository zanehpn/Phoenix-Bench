`timescale 1ns/1ps
module tb_shift_reg_gated_patch;
  localparam int unsigned DEPTH = 2;
  localparam int unsigned DATA_W = 8;

  logic clk, rst_n;
  logic valid_in, valid_out;
  logic [DATA_W-1:0] data_in, data_out;
  int cycle_cnt;

  shift_reg_gated #(
    .Depth (DEPTH),
    .dtype (logic [DATA_W-1:0])
  ) dut (
    .clk_i   (clk),
    .rst_ni  (rst_n),
    .valid_i (valid_in),
    .data_i  (data_in),
    .valid_o (valid_out),
    .data_o  (data_out)
  );

  initial clk = 0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 0; valid_in = 0; data_in = '0; cycle_cnt = 0;
    repeat (3) @(posedge clk);
    rst_n = 1;
    @(posedge clk);
    // Push 0xA1
    valid_in = 1'b1; data_in = 8'hA1; @(posedge clk);
    valid_in = 1'b0;
    // Wait for valid_o up to 10 cycles
    for (int i = 0; i < 10; i++) begin
      @(posedge clk);
      if (valid_out) begin
        if (data_out !== 8'hA1)
          $fatal(1, "FAIL: shift_reg_gated output=%h, expected=A1", data_out);
        $display("PASS: shift_reg_gated forwards 0xA1 with valid handshake.");
        $finish;
      end
    end
    $fatal(1, "FAIL: shift_reg_gated valid_o never asserted.");
  end
endmodule

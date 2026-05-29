module tb_corev_verilator_wrapper;
  logic clk;
  logic rst_n;
  logic fetch_enable;
  logic boot_seen;

  tb_top_verilator dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .fetch_enable_i(fetch_enable),
    .boot_seen_o(boot_seen)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 1'b0;
    fetch_enable = 1'b0;
    repeat (2) @(posedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    fetch_enable = 1'b1;
    @(negedge clk);
    #1;
    if (boot_seen !== 1'b1) begin
      $fatal(1, "FAIL: Verilator wrapper did not propagate fetch_enable_i");
    end
    $display("PASS: core-v-verif Verilator wrapper compiles and propagates fetch_enable_i");
    $finish;
  end
endmodule

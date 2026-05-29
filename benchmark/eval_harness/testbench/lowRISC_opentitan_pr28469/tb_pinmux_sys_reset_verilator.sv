module tb_pinmux_sys_reset;
  logic clk = 1'b0;
  logic rst_ni = 1'b0;
  logic rst_sys_ni = 1'b1;
  logic strap_sample;
  logic strap_value;
  logic strap_out;

  always #5 clk = ~clk;

  pinmux dut (
    .clk_i(clk),
    .rst_ni(rst_ni),
    .rst_sys_ni(rst_sys_ni),
    .strap_sample_i(strap_sample),
    .strap_value_i(strap_value),
    .strap_value_o(strap_out)
  );

  initial begin
    strap_sample = 1'b0;
    strap_value = 1'b0;
    repeat (2) @(posedge clk);
    rst_ni = 1'b1;

    @(negedge clk);
    strap_value = 1'b1;
    strap_sample = 1'b1;
    @(posedge clk);
    #1;
    strap_sample = 1'b0;

    if (strap_out !== 1'b1) begin
      $fatal(1, "setup failed: strap did not sample high");
    end

    @(negedge clk);
    rst_sys_ni = 1'b0;
    @(posedge clk);
    #1;

    if (strap_out !== 1'b1) begin
      $fatal(1, "sys reset cleared sampled strap value");
    end

    $display("PASS: pinmux sampled strap state is independent of sys reset.");
    $finish;
  end
endmodule

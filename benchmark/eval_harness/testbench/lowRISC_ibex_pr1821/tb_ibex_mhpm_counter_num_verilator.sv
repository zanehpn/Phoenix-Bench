module tb_ibex_mhpm_counter_num;
  logic clk = 1'b0;
  logic rst_ni = 1'b0;
  logic cfg_valid;
  logic created;
  logic [31:0] mhpm_created;

  always #5 clk = ~clk;

  ibex_simple_system_cosim_checker dut (
    .clk_i(clk),
    .rst_ni(rst_ni),
    .cfg_valid_i(cfg_valid),
    .mhpm_counter_num_i(32'd29),
    .cosim_created_o(created),
    .created_mhpm_counter_num_o(mhpm_created)
  );

  initial begin
    cfg_valid = 1'b0;
    repeat (2) @(posedge clk);
    rst_ni = 1'b1;
    @(negedge clk);
    cfg_valid = 1'b1;
    @(posedge clk);
    #1;
    cfg_valid = 1'b0;

    if (created !== 1'b1) begin
      $fatal(1, "cosim checker did not create a configuration");
    end
    if (mhpm_created !== 32'd29) begin
      $fatal(1, "MHPM counter count was not forwarded: got %0d expected 29", mhpm_created);
    end

    $display("PASS: Ibex cosim checker forwards MHPMCounterNum.");
    $finish;
  end
endmodule

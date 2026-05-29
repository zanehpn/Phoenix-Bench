module tb_cheshire_spm_execute_region;
  logic clk = 1'b0;
  logic rst_ni = 1'b0;
  logic valid;
  logic [63:0] addr;
  logic execute;
  logic uncached_rule;

  always #5 clk = ~clk;

  cheshire_spm_execute_region dut (
    .clk_i(clk),
    .rst_ni(rst_ni),
    .valid_i(valid),
    .addr_i(addr),
    .execute_o(execute),
    .uncached_rule_o(uncached_rule)
  );

  task automatic sample(input logic [63:0] sample_addr);
    @(negedge clk);
    addr = sample_addr;
    valid = 1'b1;
    @(posedge clk);
    #1;
    valid = 1'b0;
  endtask

  initial begin
    valid = 1'b0;
    addr = '0;
    repeat (2) @(posedge clk);
    rst_ni = 1'b1;

    sample(64'h1400_0040);
    if (execute !== 1'b1) begin
      $fatal(1, "uncached SPM address was not executable");
    end
    if (uncached_rule !== 1'b1) begin
      $fatal(1, "uncached SPM execute did not use a dedicated AmSpmUnc rule");
    end

    sample(64'h1000_0040);
    if (execute !== 1'b1 || uncached_rule !== 1'b0) begin
      $fatal(1, "cached SPM should execute through the cached rule only");
    end

    $display("PASS: Cheshire exposes cached and uncached SPM as distinct execute regions.");
    $finish;
  end
endmodule

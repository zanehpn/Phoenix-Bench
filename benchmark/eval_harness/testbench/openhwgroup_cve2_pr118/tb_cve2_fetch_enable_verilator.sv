module tb_cve2_fetch_enable;
  logic       clk;
  logic       rst_n;
  logic       fetch_enable;
  logic       instr_req;
  logic       pc_set;
  logic [1:0] state;

  cve2_controller dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .fetch_enable_i(fetch_enable),
    .instr_req_o(instr_req),
    .pc_set_o(pc_set),
    .state_o(state)
  );

  initial clk = 1'b0;
  always #5 clk = ~clk;

  initial begin
    rst_n = 1'b0;
    fetch_enable = 1'b0;

    repeat (2) @(posedge clk);
    rst_n = 1'b1;

    repeat (3) @(negedge clk);
    #1;
    if (state !== 2'd0 || instr_req !== 1'b0) begin
      $fatal(1, "FAIL: controller left RESET before fetch_enable_i was asserted; state=%0d instr_req=%0b", state, instr_req);
    end

    fetch_enable = 1'b1;
    @(negedge clk);
    #1;
    if (state !== 2'd1 || instr_req !== 1'b1) begin
      $fatal(1, "FAIL: controller did not enter BOOT_SET after fetch_enable_i; state=%0d instr_req=%0b", state, instr_req);
    end

    $display("PASS: cve2 controller gates reset exit with fetch_enable_i");
    $finish;
  end
endmodule

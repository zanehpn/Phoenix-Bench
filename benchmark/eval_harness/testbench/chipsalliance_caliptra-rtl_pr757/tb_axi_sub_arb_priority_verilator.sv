module tb_axi_sub_arb_priority;
  logic clk = 1'b0;
  logic rst_n = 1'b0;

  logic r_dv, r_last, r_hld;
  logic w_dv, w_last, w_hld;
  logic hld;
  logic dv, write, last;
  logic [31:0] addr;

  always #5 clk = ~clk;

  axi_sub_arb dut (
    .clk(clk),
    .rst_n(rst_n),
    .r_dv(r_dv),
    .r_addr(32'h0000_1000),
    .r_user('0),
    .r_id('0),
    .r_size(3'd2),
    .r_last(r_last),
    .r_hld(r_hld),
    .r_err(),
    .r_rdata(),
    .w_dv(w_dv),
    .w_addr(32'h0000_2000),
    .w_user('0),
    .w_id('0),
    .w_wdata(32'hca11_7570),
    .w_wstrb(4'hf),
    .w_size(3'd2),
    .w_last(w_last),
    .w_hld(w_hld),
    .w_err(),
    .dv(dv),
    .addr(addr),
    .write(write),
    .user(),
    .id(),
    .wdata(),
    .wstrb(),
    .size(),
    .last(last),
    .hld(hld),
    .rd_err(1'b0),
    .wr_err(1'b0),
    .rdata(32'h0)
  );

  task automatic tick;
    @(posedge clk);
    #1;
  endtask

  initial begin
    r_dv = 1'b0;
    r_last = 1'b1;
    w_dv = 1'b0;
    w_last = 1'b1;
    hld = 1'b0;

    repeat (2) tick();
    rst_n = 1'b1;
    tick();

    // Finish a write beat to toggle fairness priority toward reads.
    w_dv = 1'b1;
    w_last = 1'b1;
    tick();
    w_dv = 1'b0;
    tick();

    if (dut.r_pri !== 1'b1) begin
      $fatal(1, "setup failed: expected read priority after completed write");
    end

    // A final write beat is present but held by the component. Even though no
    // read is present yet, the arbiter must remember that the write transfer is
    // in progress.
    w_dv = 1'b1;
    w_last = 1'b1;
    hld = 1'b1;
    tick();

    // When the hold releases and a read appears, buggy RTL lets the read steal
    // the component interface. Fixed RTL keeps the write selected.
    r_dv = 1'b1;
    hld = 1'b0;
    #1;
    if (write !== 1'b1 || w_hld !== 1'b0 || r_hld !== 1'b1 || addr !== 32'h0000_2000) begin
      $fatal(1, "write priority was not retained for held final beat: write=%0b w_hld=%0b r_hld=%0b addr=%h r_pri=%0b",
             write, w_hld, r_hld, addr, dut.r_pri);
    end

    $display("PASS: AXI subordinate arbiter retains write priority while the final beat is held.");
    $finish;
  end
endmodule

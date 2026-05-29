module tb_sky130_dffe_polarity;
  logic clk;
  logic en_n;
  logic d;
  logic q;

  \$dffe #(
    .WIDTH(1),
    .CLK_POLARITY(1'b1),
    .EN_POLARITY(1'b0)
  ) dut (
    .CLK(clk),
    .D(d),
    .EN(en_n),
    .Q(q)
  );

  initial begin
    clk = 1'b0;
    en_n = 1'b1;
    d = 1'b0;
    #1;
    if (q !== 1'b0) begin
      $fatal(1, "FAIL: mapped DFFE should initialize to zero, got %0b", q);
    end

    d = 1'b1;
    en_n = 1'b0;
    #4 clk = 1'b1;
    #1;
    if (q !== 1'b1) begin
      $fatal(1, "FAIL: EN_POLARITY=0 must enable capture when EN is low");
    end

    clk = 1'b0;
    d = 1'b0;
    en_n = 1'b1;
    #4 clk = 1'b1;
    #1;
    if (q !== 1'b1) begin
      $fatal(1, "FAIL: disabled active-low EN must hold previous Q");
    end

    $display("PASS: sky130 DFFE mapping honors EN_POLARITY");
    $finish;
  end
endmodule

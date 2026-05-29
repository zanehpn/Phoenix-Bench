module tb_a2o_generate_guard;
    logic clk;
    logic rst_n;
    logic enable_i;
    logic seen_o;
    logic generate_style_ok_o;

    tri_generate_guard dut (
        .clk,
        .rst_n,
        .enable_i,
        .seen_o,
        .generate_style_ok_o
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    initial begin
        rst_n = 1'b0;
        enable_i = 1'b0;
        repeat (2) @(posedge clk);
        rst_n = 1'b1;

        @(negedge clk);
        enable_i = 1'b1;
        @(posedge clk);
        #1;
        if (!seen_o) begin
            $fatal(1, "sequential guard did not observe enable_i");
        end
        if (!generate_style_ok_o) begin
            $fatal(1, "generate block is still in the old unconditional begin form");
        end
        $finish;
    end
endmodule

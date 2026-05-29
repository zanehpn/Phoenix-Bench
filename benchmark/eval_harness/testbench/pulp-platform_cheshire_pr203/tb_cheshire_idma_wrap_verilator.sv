module tb_cheshire_idma_wrap;
    logic clk_i;
    logic rst_ni;
    logic axi_slv_valid_i;
    logic [31:0] axi_slv_addr_i;
    logic axi_slv_ready_o;
    logic dma_start_o;
    logic [31:0] dma_addr_o;
    logic translator_busy_o;

    cheshire_idma_wrap dut (
        .clk_i,
        .rst_ni,
        .axi_slv_valid_i,
        .axi_slv_addr_i,
        .axi_slv_ready_o,
        .dma_start_o,
        .dma_addr_o,
        .translator_busy_o
    );

    initial clk_i = 1'b0;
    always #5 clk_i = ~clk_i;

    initial begin
        rst_ni = 1'b0;
        axi_slv_valid_i = 1'b0;
        axi_slv_addr_i = '0;
        repeat (2) @(posedge clk_i);
        rst_ni = 1'b1;

        @(negedge clk_i);
        axi_slv_addr_i = 32'h0000_1040;
        axi_slv_valid_i = 1'b1;
        @(posedge clk_i);
        #1;
        if (!axi_slv_ready_o) begin
            $fatal(1, "AXI register request was not accepted");
        end
        if (!translator_busy_o) begin
            $fatal(1, "translator did not report activity during the request");
        end
        if (!dma_start_o) begin
            $fatal(1, "1D DMA start write was dropped by the register translator");
        end
        if (dma_addr_o != 32'h0000_1040) begin
            $fatal(1, "DMA address mismatch: got %h", dma_addr_o);
        end

        @(negedge clk_i);
        axi_slv_valid_i = 1'b0;
        @(posedge clk_i);
        #1;
        if (dma_start_o) begin
            $fatal(1, "DMA start pulse lasted more than one cycle");
        end
        $finish;
    end
endmodule

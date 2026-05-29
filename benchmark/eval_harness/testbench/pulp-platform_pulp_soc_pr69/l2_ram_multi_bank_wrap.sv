`include "soc_mem_map.svh"

module l2_ram_multi_bank_wrap #(
  parameter int unsigned NB_BANKS = 4,
  parameter int unsigned BANK_SIZE_INTL_SRAM = 32768
)(
  input  logic clk_i,
  input  logic rst_ni,
  input  logic init_ni,
  input  logic test_mode_i
);

  // 1) 实例化 interface（数组），注意：interface 本身不带 clk/rst 端口，所以直接声明即可
  XBAR_TCDM_BUS mem_slave_if   [NB_BANKS] ();
  XBAR_TCDM_BUS mem_pri_slave_if[2]       ();

  // 2) 给“Master->Slave”的输入信号默认值，保证 idle（只是为了过编译/少X）
  genvar i;
  generate
    for (i = 0; i < NB_BANKS; i++) begin : GEN_TIEOFF_INTL
      // 这些是 Slave modport 的 input：req/add/wen/wdata/be
      // 对应在 interface 里是 logic 变量，所以可以在 wrapper 里驱动
      assign mem_slave_if[i].req   = 1'b0;
      assign mem_slave_if[i].add   = 32'h0;
      assign mem_slave_if[i].wen   = 1'b1;      // wen=1 => 不写（因为 DUT 里用 ~wen 当 we_i）
      assign mem_slave_if[i].wdata = 32'h0;
      assign mem_slave_if[i].be    = 4'h0;
    end

    for (i = 0; i < 2; i++) begin : GEN_TIEOFF_PRI
      assign mem_pri_slave_if[i].req   = 1'b0;
      assign mem_pri_slave_if[i].add   = 32'h0;
      assign mem_pri_slave_if[i].wen   = 1'b1;
      assign mem_pri_slave_if[i].wdata = 32'h0;
      assign mem_pri_slave_if[i].be    = 4'h0;
    end
  endgenerate

  // 3) 实例化 DUT，并把 interface 用 .Slave modport 连接进去
  l2_ram_multi_bank #(
    .NB_BANKS(NB_BANKS),
    .BANK_SIZE_INTL_SRAM(BANK_SIZE_INTL_SRAM)
  ) dut (
    .clk_i       (clk_i),
    .rst_ni      (rst_ni),
    .init_ni     (init_ni),
    .test_mode_i (test_mode_i),
    .mem_slave   (mem_slave_if),      // 类型匹配：XBAR_TCDM_BUS.Slave mem_slave[NB_BANKS]
    .mem_pri_slave(mem_pri_slave_if)  // 类型匹配：XBAR_TCDM_BUS.Slave mem_pri_slave[2]
  );

endmodule

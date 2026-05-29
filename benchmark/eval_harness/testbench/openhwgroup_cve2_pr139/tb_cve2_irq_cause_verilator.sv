module tb_cve2_irq_cause;
  logic [31:0] csr_mtvec;
  logic [15:0] irq_fast;
  logic        irq_external;
  logic        irq_software;
  logic        irq_timer;
  logic        irq_nm;
  logic [6:0]  exc_cause;
  logic [31:0] exc_pc;

  cve2_irq_cause dut (
    .csr_mtvec_i(csr_mtvec),
    .irq_fast_i(irq_fast),
    .irq_external_i(irq_external),
    .irq_software_i(irq_software),
    .irq_timer_i(irq_timer),
    .irq_nm_i(irq_nm),
    .exc_cause_o(exc_cause),
    .exc_pc_o(exc_pc)
  );

  initial begin
    csr_mtvec = 32'h0000_4000;
    irq_fast = '0;
    irq_external = 1'b0;
    irq_software = 1'b0;
    irq_timer = 1'b0;
    irq_nm = 1'b0;
    #1;

    irq_nm = 1'b1;
    #1;
    if (exc_cause !== 7'h60 || exc_pc !== 32'h0000_4080) begin
      $fatal(1, "FAIL: NMI must be cause 32/vector +0x80, got cause=%02h pc=%08h", exc_cause, exc_pc);
    end

    irq_nm = 1'b0;
    irq_fast = 16'h8000;
    #1;
    if (exc_cause !== 7'h5f || exc_pc !== 32'h0000_407c) begin
      $fatal(1, "FAIL: fast IRQ15 must be cause 31/vector +0x7c, got cause=%02h pc=%08h", exc_cause, exc_pc);
    end

    $display("PASS: cve2 IRQ cause width separates NMI from fast IRQ15");
    $finish;
  end
endmodule

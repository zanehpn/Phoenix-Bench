`timescale 1ns/1ps

module tb_i2c_top_reset;

  // clock
  logic clk;
  initial clk = 1'b0;
  always #5 clk = ~clk; // 100MHz

  logic strobe_400kHz;
  initial begin
    strobe_400kHz = 1'b0;
    forever begin
      repeat (20) @(posedge clk);
      strobe_400kHz <= 1'b1;
      @(posedge clk);
      strobe_400kHz <= 1'b0;
    end
  end

  // I2C inout must be net
  tri i2c_scl;
  tri i2c_sda;
  pullup(i2c_scl);
  pullup(i2c_sda);

  logic areset_n;

  int error_count = 0;

  // Functional coverage for I2C reset bug fix
  logic areset_n_sampled;
  logic i2c_enable_sampled;
  logic i2c_read_write_sampled;
  logic [15:0] i2c_reg_addr_sampled;
  logic [6:0] i2c_reg_cnt_sampled;
  logic i2c_reg_cnt_done_sampled;
  logic strobe_sampled;

  always @(posedge clk) begin
    areset_n_sampled      <= areset_n;
    strobe_sampled        <= strobe_400kHz;
  end

  covergroup cg_inst @(posedge clk);
    // Cover async reset states (bug: reset polarity was wrong)
    cp_areset_n: coverpoint areset_n {
      bins asserted   = {1'b0};
      bins deasserted = {1'b1};
    }

    // Cover reset transitions (key to the async reset fix)
    cp_reset_transition: coverpoint areset_n {
      bins assert_reset   = (1'b1 => 1'b0);
      bins deassert_reset = (1'b0 => 1'b1);
    }

    // Cover strobe activity during reset
    cp_strobe: coverpoint strobe_400kHz {
      bins active   = {1'b1};
      bins inactive = {1'b0};
    }

    // Cross: reset state vs strobe (bug involved reset timing w.r.t. strobe)
    cx_reset_strobe: cross cp_areset_n, cp_strobe;

    // Cover i2c_enable reset value (should be 1 in reset)
    cp_i2c_enable: coverpoint dut.i2c_enable {
      bins enabled  = {1'b1};
      // i2c_enable is always 1 in this design (always re-enabled on strobe)
      ignore_bins ig_disabled = {1'b0};
    }

    // Cover i2c_read_write reset value (should be 0 in reset)
    cp_i2c_rw: coverpoint dut.i2c_read_write {
      bins read  = {1'b0};
      // i2c_read_write is always 0 in this design (write-only I2C init FSM)
      ignore_bins ig_write = {1'b1};
    }

    // Cross: reset with enable and rw to verify reset values
    cx_reset_enable: cross cp_areset_n, cp_i2c_enable;
    cx_reset_rw: cross cp_areset_n, cp_i2c_rw;
  endgroup

  cg_inst cg_inst_handle = new();

  task automatic check(string name, bit cond);
    if (!cond) begin
      $display("[%0t] FAIL: %s", $time, name);
      error_count++;
    end else begin
      $display("[%0t] PASS: %s", $time, name);
    end
  endtask

  i2c_top dut (
    clk,            // 1: clk
    strobe_400kHz,  // 2: strobe_400kHz
    areset_n,       // 3: reset  (intentional mismatch)
    i2c_scl,        // 4: i2c_scl
    i2c_sda         // 5: i2c_sda
  );

  initial begin
    // start not in reset
    areset_n = 1'b1;
    repeat (5) @(posedge clk);

    // Assert reset low (patch 后应当 reset)
    $display("\n[%0t] Assert reset (areset_n=0)\n", $time);
    areset_n = 1'b0;
    #1; // async reset should take effect immediately in patched design
    @(posedge clk);

    // 下面用层次引用检查 i2c_top 里 always_ff 复位赋的那些寄存器
    // patch2 里 reset 时：
    //   i2c_enable <= 1
    //   i2c_read_write <= 0
    //   i2c_reg_addr <= 0
    //   i2c_reg_cnt <= 0
    //   i2c_reg_cnt_done <= 0
    check("i2c_enable reset to 1",      dut.i2c_enable       === 1'b1);
    check("i2c_read_write reset to 0",  dut.i2c_read_write   === 1'b0);
    check("i2c_reg_addr reset to 0",    dut.i2c_reg_addr     === 16'h0000);
    check("i2c_reg_cnt reset to 0",     dut.i2c_reg_cnt      === 7'h00);
    check("i2c_reg_cnt_done reset to 0",dut.i2c_reg_cnt_done === 1'b0);

    // Deassert reset
    $display("\n[%0t] Deassert reset (areset_n=1)\n", $time);
    areset_n = 1'b1;
    repeat (3) @(posedge clk);

    // 再次确认寄存器不是 X（至少 reset 后稳定）
    check("i2c_enable not X after reset release", dut.i2c_enable !== 1'bx);

    // Run for enough cycles to let the I2C FSM progress and toggle i2c_read_write
    // and i2c_enable through their operational values
    repeat (500) @(posedge clk);

    // Pulse reset again with strobe active to ensure cross coverage
    @(posedge clk);
    // Wait for strobe to be active then assert reset
    wait (strobe_400kHz == 1'b1);
    areset_n = 1'b0;
    @(posedge clk);
    @(posedge clk);
    areset_n = 1'b1;
    repeat (3) @(posedge clk);

    $display("\nTest finished. error_count=%0d", error_count);
    $display("Functional Coverage: %.1f%%", cg_inst_handle.get_coverage());
    if (error_count == 0) begin
      $display("TEST PASSED");
      $finish;
    end else begin
      $display("TEST FAILED");
      $fatal(1, "TEST FAILED");
    end
  end


  initial begin
    $dumpfile("tb_i2c_reset.vcd");
    $dumpvars(0);
  end

endmodule

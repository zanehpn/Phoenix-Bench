`timescale 1ns/1ps

module tb_pad_io_patch;

  logic clk;
  logic reset;

  logic MODE;
  logic SMS;

  logic P_UP, P_DOWN, P_LEFT, P_RIGHT;
  logic P_A, P_B, P_C, P_START, P_MODE, P_X, P_Y, P_Z;

  logic GUN_EN, GUN_TYPE, GUN_SENSOR, GUN_A, GUN_B, GUN_C, GUN_START;
  logic MOUSE_EN, MOUSE_FLIPY;
  logic [24:0] MOUSE;

  logic [6:0] port_in;
  logic [6:0] port_dir;
  wire  [6:0] port_out;

  // DUT
  pad_io dut (
    .clk(clk),
    .reset(reset),

    .MODE(MODE),
    .SMS(SMS),

    .P_UP(P_UP),
    .P_DOWN(P_DOWN),
    .P_LEFT(P_LEFT),
    .P_RIGHT(P_RIGHT),
    .P_A(P_A),
    .P_B(P_B),
    .P_C(P_C),
    .P_START(P_START),
    .P_MODE(P_MODE),
    .P_X(P_X),
    .P_Y(P_Y),
    .P_Z(P_Z),

    .GUN_EN(GUN_EN),
    .GUN_TYPE(GUN_TYPE),
    .GUN_SENSOR(GUN_SENSOR),
    .GUN_A(GUN_A),
    .GUN_B(GUN_B),
    .GUN_C(GUN_C),
    .GUN_START(GUN_START),

    .MOUSE_EN(MOUSE_EN),
    .MOUSE_FLIPY(MOUSE_FLIPY),
    .MOUSE(MOUSE),

    .port_out(port_out),
    .port_in(port_in),
    .port_dir(port_dir)
  );

  // clock
  initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
  end

  initial begin
    // Defaults
    MODE        = 1'b1;
    SMS         = 1'b1;        // <-- force 4'b1XXX branch

    // Disable other devices so pdata is used
    GUN_EN      = 1'b0;
    GUN_TYPE    = 1'b0;
    GUN_SENSOR  = 1'b0;
    GUN_A       = 1'b0;
    GUN_B       = 1'b0;
    GUN_C       = 1'b0;
    GUN_START   = 1'b0;

    MOUSE_EN    = 1'b0;
    MOUSE_FLIPY = 1'b0;
    MOUSE       = '0;

    // Make output drive from internal pdata: port_out = {1'b1, pdata}
    port_dir    = 7'b1111111;
    port_in     = 7'b0000000;

    // Choose inputs to distinguish patch:
    // Patch-before: pdata[5]=~P_B
    // Patch-after : pdata[5]=~P_C
    //
    // Set P_B=1 => ~P_B=0
    // Set P_C=0 => ~P_C=1   => this bit flips ONLY after patch
    P_B    = 1'b1;
    P_C    = 1'b0;

    // Other keys (don’t care but set deterministic)
    P_A    = 1'b1;
    P_UP   = 1'b0;
    P_DOWN = 1'b0;
    P_LEFT = 1'b0;
    P_RIGHT= 1'b0;

    P_START= 1'b0;
    P_MODE = 1'b0;
    P_X    = 1'b0;
    P_Y    = 1'b0;
    P_Z    = 1'b0;

    // reset pulse
    reset = 1'b1;
    repeat (2) @(posedge clk);
    reset = 1'b0;
    repeat (2) @(posedge clk);

    // Wait one more cycle to ensure pdata updated at posedge
    @(posedge clk);

    $display("[TB] port_out = %b", port_out);
    $display("[TB] Expect AFTER patch: port_out[6]=1 and port_out[5]=1 (because ~P_C=1)");

    // Check: since port_dir all 1 and MOUSE/GUN disabled, port_out should be {1'b1, pdata}
    if (port_out[6] !== 1'b1) begin
      $fatal(1, "FAIL: port_out[6] should be 1 (selector bit), got %b", port_out[6]);
    end

    // This is the patch discriminator:
    // - Before patch => port_out[5]=~P_B=0  => FAIL
    // - After patch  => port_out[5]=~P_C=1  => PASS
    if (port_out[5] !== 1'b1) begin
      $display("FAIL (expected after patch): port_out[5]=%b. This matches PRE-patch behavior (~P_B).", port_out[5]);
      $fatal(1, "FAIL");
    end else begin
      $display("PASS: port_out[5]=1 matches PATCHED behavior (~P_C).");
    end

    // ---- Additional stimulus to hit remaining coverage bins ----

    // Test with P_C=1 -> ~P_C=0 -> port_out[5]=0
    P_C = 1'b1;
    P_B = 1'b0;
    @(posedge clk);
    @(posedge clk);
    $display("[TB] port_out (P_C=1,P_B=0) = %b", port_out);

    // Test with SMS=0 (non-SMS mode)
    SMS = 1'b0;
    P_C = 1'b0;
    P_B = 1'b1;
    @(posedge clk);
    @(posedge clk);
    $display("[TB] port_out (SMS=0,P_C=0,P_B=1) = %b", port_out);

    // SMS=0 with P_C=1, P_B=0
    P_C = 1'b1;
    P_B = 1'b0;
    @(posedge clk);
    @(posedge clk);
    $display("[TB] port_out (SMS=0,P_C=1,P_B=0) = %b", port_out);

    // SMS=1 with P_B=0, P_C=1
    SMS = 1'b1;
    P_B = 1'b0;
    P_C = 1'b1;
    @(posedge clk);
    @(posedge clk);

    // SMS=1 with P_B=1, P_C=1
    P_B = 1'b1;
    P_C = 1'b1;
    @(posedge clk);
    @(posedge clk);

    $display("Functional Coverage: %.1f%%", cg_inst.get_coverage());
    $finish;
  end


  initial begin
    $dumpfile("tb_pad_io_patch.vcd");
    $dumpvars(0);
  end

  // ---------------------------------------------------------------
  // Patch-focused functional coverage
  // ---------------------------------------------------------------
  // Patch: In SMS mode (4'b1XXX), pdata[5] changed from ~P_B to ~P_C
  //        and pdata[4] changed from ~P_A to ~P_B

  covergroup cg_patch @(posedge clk);
    cp_sms: coverpoint SMS {
      bins sms_on  = {1'b1};
      bins sms_off = {1'b0};
    }
    cp_p_b: coverpoint P_B {
      bins lo = {1'b0};
      bins hi = {1'b1};
    }
    cp_p_c: coverpoint P_C {
      bins lo = {1'b0};
      bins hi = {1'b1};
    }
    cp_port_out_5: coverpoint port_out[5] {
      bins lo = {1'b0};
      bins hi = {1'b1};
    }
    // Cross: SMS mode with P_C value - the patch changes pdata[5] to ~P_C
    cx_sms_pc: cross cp_sms, cp_p_c;
    // Cross: SMS mode with P_B value - the patch changes pdata[4] to ~P_B
    cx_sms_pb: cross cp_sms, cp_p_b;
  endgroup

  cg_patch cg_inst = new();

endmodule

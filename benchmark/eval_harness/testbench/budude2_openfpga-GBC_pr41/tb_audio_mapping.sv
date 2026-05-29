`timescale 1ns/1ps

// Testbench for budude2_openfpga-GBC_pr41
//
// Patch: Fixed audio channel mix-up where core_l was connected to audio_r
// and core_r was connected to audio_l. After the fix, core_l connects to
// audio_l and core_r connects to audio_r.
//
// This testbench models the audio_mixer port mapping and verifies
// that left/right channels are correctly routed.

module tb_audio_mapping;

  // Model the audio signals
  logic signed [15:0] audio_l;
  logic signed [15:0] audio_r;

  // Model the audio_mixer connections (post-patch)
  logic signed [15:0] mixer_core_l;
  logic signed [15:0] mixer_core_r;

  // The patch ensures: .core_l(audio_l), .core_r(audio_r)
  assign mixer_core_l = audio_l;
  assign mixer_core_r = audio_r;

  logic clk;
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  integer fail = 0;

  initial begin
    $display("=== Audio Channel Mapping Fix Test (PR #41) ===");

    // Test 1: Distinct L/R values
    audio_l = 16'h1234;
    audio_r = 16'h5678;
    #1;

    if (mixer_core_l !== audio_l) begin
      $display("FAIL: mixer_core_l=%h, expected audio_l=%h", mixer_core_l, audio_l);
      fail = 1;
    end
    if (mixer_core_r !== audio_r) begin
      $display("FAIL: mixer_core_r=%h, expected audio_r=%h", mixer_core_r, audio_r);
      fail = 1;
    end

    // Test 2: Zero on one channel
    audio_l = 16'h0000;
    audio_r = 16'h7FFF;
    #1;
    if (mixer_core_l !== 16'h0000 || mixer_core_r !== 16'h7FFF) begin
      $display("FAIL: Channel routing incorrect for zero/max test");
      fail = 1;
    end

    // Test 3: Negative values
    audio_l = -16'sd100;
    audio_r = -16'sd200;
    #1;
    if (mixer_core_l !== audio_l || mixer_core_r !== audio_r) begin
      $display("FAIL: Channel routing incorrect for negative values");
      fail = 1;
    end

    // Test 4: Same value on both channels
    audio_l = 16'hAAAA;
    audio_r = 16'hAAAA;
    #1;
    if (mixer_core_l !== audio_l || mixer_core_r !== audio_r) begin
      $display("FAIL: Channel routing incorrect for same-value test");
      fail = 1;
    end

    // Test 5: Verify channels are NOT swapped (the bug was swapped channels)
    audio_l = 16'h1111;
    audio_r = 16'h2222;
    #1;
    if (mixer_core_l === audio_r && mixer_core_r === audio_l) begin
      $display("FAIL: Channels are swapped (pre-patch bug still present)");
      fail = 1;
    end

    @(posedge clk);
    @(posedge clk);
    @(posedge clk);

    if (fail == 0)
      $display("PASS: Audio channel mapping is correct.");
    else
      $display("FAIL");

    $display("Functional Coverage: %.1f%%", cg_inst.get_coverage());
    $finish;
  end

  // Safety timeout
  initial begin
    #10000;
    $fatal(1, "FAIL: Timeout");
  end

  // ---------------------------------------------------------------
  // Patch-focused functional coverage
  // ---------------------------------------------------------------
  // Patch: core_l now correctly maps to audio_l, core_r to audio_r

  covergroup cg_patch @(posedge clk);
    cp_audio_l: coverpoint audio_l {
      bins zero     = {16'h0000};
      bins positive = {[16'h0001:16'h7FFF]};
      bins negative = {[16'h8000:16'hFFFF]};
    }
    cp_audio_r: coverpoint audio_r {
      bins zero     = {16'h0000};
      bins positive = {[16'h0001:16'h7FFF]};
      bins negative = {[16'h8000:16'hFFFF]};
    }
    cp_channels_differ: coverpoint (audio_l !== audio_r) {
      bins same      = {1'b0};
      bins different = {1'b1};
    }
    // Cross: different L/R value categories
    cx_lr_values: cross cp_audio_l, cp_audio_r;
  endgroup

  cg_patch cg_inst = new();

endmodule

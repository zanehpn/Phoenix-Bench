`timescale 1ns/1ps
// ------------------------------------------------------------
// TB
// ------------------------------------------------------------
module tb_dmi_jtag_glitch_checks;

  // Clocks / resets
  logic clk_i;
  logic rst_ni;

  logic tck_i;
  logic tms_i;
  logic trst_ni;
  logic td_i;
  wire  td_o;
  wire  tdo_oe_o;

  // DMI handshake to/from core
  dm::dmi_req_t  dmi_req_o;
  logic          dmi_req_valid_o;
  logic          dmi_req_ready_i;

  dm::dmi_resp_t dmi_resp_i;
  logic          dmi_resp_valid_i;
  logic          dmi_resp_ready_o;

  logic          testmode_i;
  wire           dmi_rst_no;

  // ---- Patch-related functional coverage ----
  // PR123: dmi_rst_no must be synchronous, glitch-free, 1-cycle pulse
  covergroup cg_inst @(posedge clk_i);
    cp_rst_ni: coverpoint rst_ni {
      bins in_reset = {1'b0};
      bins active   = {1'b1};
    }
    cp_trst_ni: coverpoint trst_ni {
      bins in_reset = {1'b0};
      bins active   = {1'b1};
    }
    cp_dmi_rst_no: coverpoint dmi_rst_no {
      bins low  = {1'b0};
      bins high = {1'b1};
    }
    cp_dmi_req_valid: coverpoint dmi_req_valid_o {
      bins idle   = {1'b0};
      bins active = {1'b1};
    }
    cross_rst_trst: cross cp_rst_ni, cp_trst_ni;
    cross_rst_dmi: cross cp_rst_ni, cp_dmi_rst_no;
  endgroup

  cg_inst cg = new();

  // Clock gen
  initial clk_i = 1'b0;
  always #5 clk_i = ~clk_i;        // 100MHz

  initial tck_i = 1'b0;
  always #7 tck_i = ~tck_i;        // ~71.4MHz (async to clk_i)

  // Drive defaults
  initial begin
    tms_i = 1'b0;
    td_i  = 1'b0;
    testmode_i = 1'b0;

    dmi_req_ready_i   = 1'b1;
    dmi_resp_i        = '0;
    dmi_resp_valid_i  = 1'b0;

    // Resets
    rst_ni  = 1'b0;
    trst_ni = 1'b0;
    repeat (5) @(posedge clk_i);
    rst_ni  = 1'b1;
    repeat (3) @(posedge tck_i);
    trst_ni = 1'b1;
  end

  // DUT (your module)
  dmi_jtag dut (
    .clk_i,
    .rst_ni,
    .testmode_i,

    .dmi_rst_no,

    .dmi_req_o,
    .dmi_req_valid_o,
    .dmi_req_ready_i,

    .dmi_resp_i,
    .dmi_resp_ready_o,
    .dmi_resp_valid_i,

    .tck_i,
    .tms_i,
    .trst_ni,
    .td_i,
    .td_o,
    .tdo_oe_o
  );

  // ------------------------------------------------------------
  // CHECK #1: No X/Z on dmi_rst_no after rst_ni released
  // ------------------------------------------------------------
  always @(posedge clk_i) begin
    if (rst_ni) begin
      if ($isunknown(dmi_rst_no)) begin
        $error("[%0t] dmi_rst_no is X/Z", $time);
      end
    end
  end

  // ------------------------------------------------------------
  // CHECK #2: dmi_rst_no edges only at posedge clk_i (glitch detector)
  // Window method: allow changes only in the same delta-cycle as posedge clk_i.
  // ------------------------------------------------------------
  bit clk_edge_window;

  always @(posedge clk_i) begin
    clk_edge_window <= 1'b1;
    #0;                 // same simulation time slot (delta cycle)
    clk_edge_window <= 1'b0;
  end

  always @(dmi_rst_no) begin
    if (rst_ni && !clk_edge_window) begin
      $error("[%0t] GLITCH: dmi_rst_no changed outside clk_i posedge", $time);
    end
  end

  // ------------------------------------------------------------
  // CHECK #3: Active-low pulse width exactly 1 clk_i cycle
  // Meaning: if it falls (1->0) at a clk edge, it must rise back (0->1) next edge.
  //
  // This is intended for the PATCHED design where dmi_rst_no is a 1-cycle pulse.
  // For your UNPATCHED code (dmi_rst_no=rst_ni), this will likely fail.
  // ------------------------------------------------------------
  always @(posedge clk_i) begin
    if (rst_ni) begin
      // detect falling edge at sampling point
      if ($past(dmi_rst_no) == 1'b1 && dmi_rst_no == 1'b0) begin
        // next cycle must go back high
        fork
          begin
            @(posedge clk_i);
            if (dmi_rst_no !== 1'b1) begin
              $error("[%0t] dmi_rst_no low pulse not 1 cycle (did not return high)", $time);
            end
          end
        join_none
      end

      // also ensure it doesn't stay low for >1 cycle
      if ($past(dmi_rst_no) == 1'b0 && dmi_rst_no == 1'b0) begin
        $error("[%0t] dmi_rst_no stayed low > 1 clk_i cycle", $time);
      end
    end
  end

  // ------------------------------------------------------------
  // Simple stimulus to try to trigger resets / CDC activity
  // (Your patched design should generate a pulse on dmi_rst_no upon DMI clear events.)
  // Here we just toggle trst_ni to create events; real patch may also use TAP soft reset.
  // ------------------------------------------------------------
  initial begin
    // wait until released
    wait(rst_ni && trst_ni);
    repeat (20) @(posedge clk_i);

    // Toggle JTAG reset a few times (async events)
    $display("[%0t] Toggling trst_ni to try to trigger DMI reset behavior", $time);
    repeat (3) begin
      @(negedge tck_i);
      trst_ni <= 1'b0;
      repeat (5) @(posedge tck_i);
      trst_ni <= 1'b1;
      repeat (30) @(posedge clk_i);
    end

    $display("[%0t] Test finished", $time);
    $display("Functional Coverage: cg_inst = %0.2f%%", cg.get_inst_coverage());
    #100;
    $finish;
  end


  initial begin
    $dumpfile("tb.vcd");
    $dumpvars(0);
  end

endmodule

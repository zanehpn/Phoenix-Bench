`timescale 1ns/1ps

module tb;
    // short clock period to speed up sim
    reg clk = 0;
    always #1 clk = ~clk; // 1ns half period -> 2ns full period

    reg resetn = 0;

    // connect to DUT
    wire joy_clk;
    wire joy_strb;
    reg  joy_data; // driven by TB
    wire [11:0] buttons;

    // instantiate DUT with small FREQ to reduce counters
    controller_snes #(.FREQ(1000000)) dut (
        .clk(clk),
        .resetn(resetn),
        .joy_strb(joy_strb),
        .joy_clk(joy_clk),
        .joy_data(joy_data),
        .buttons(buttons)
    );

    // Patch-related functional coverage: NES vs SNES controller detection
    // The patch checks buttons_buf[15:12] to distinguish NES from SNES controllers
    logic [15:0] buttons_buf_sample;
    logic        nes_detected;
    logic        snes_detected;
    logic        scan_complete;

    assign buttons_buf_sample = dut.buttons_buf;
    assign scan_complete = (dut.state == 3);

    always @(posedge clk) begin
        if (scan_complete) begin
            nes_detected  <= (buttons_buf_sample[15:12] != 4'b0000);
            snes_detected <= (buttons_buf_sample[15:12] == 4'b0000);
        end
    end

    // [verilator-strip cg] covergroup cg_nes_controller @(posedge clk);
// [verilator-strip cg]         option.per_instance = 1;

// [verilator-strip cg]         cp_upper_bits: coverpoint buttons_buf_sample[15:12] iff (scan_complete) {
// [verilator-strip cg]             bins nes_controller = {[1:15]};
// [verilator-strip cg]             bins snes_controller = {0};
// [verilator-strip cg]         }

// [verilator-strip cg]         cp_nes_detected: coverpoint nes_detected iff (scan_complete) {
// [verilator-strip cg]             bins detected = {1};
// [verilator-strip cg]             bins not_detected = {0};
// [verilator-strip cg]         }

// [verilator-strip cg]         cp_buttons_output: coverpoint buttons iff (scan_complete) {
// [verilator-strip cg]             bins nes_mapped = {12'h0FF};
// [verilator-strip cg]             bins other_vals[] = default;
// [verilator-strip cg]         }
// [verilator-strip cg]     endgroup

    // [verilator-strip cg-inst] cg_nes_controller cg_inst = new();

    initial begin
        $dumpfile("tb_controller_snes.vcd");
        $dumpvars(0, tb);

        // initialize inputs
        joy_data = 0; // set to 0 so ~joy_data == 1 -> buttons_buf will be filled with 1s
        #5;
        // release reset after a few cycles
        resetn = 0;
        repeat (5) @(posedge clk);
        resetn = 1;

        // Wait sufficient cycles for one full scan to complete.
        // For FREQ=1_000_000 our estimate: ~ 12 cycles latch + 16*(2*TIME_6US) where TIME_6US = 6 -> ~ 204 cycles.
        // We run a safe margin.
        repeat (2000) @(posedge clk);

        // Now check DUT output
        $display("DUT buttons = 0x%03x", buttons);
        if (buttons === 12'h0FF) begin
            $display("PASS: Detected modified (+) behaviour (NES-style mapping).");
        end else begin
            $fatal(1, "FAIL: Detected original (-) behaviour or unexpected result.");
            $display("Expected 0x0FF for modified behaviour. Got 0x%03x", buttons);
        end

        // ---- Now test SNES controller scenario ----
        // Set joy_data=1 so ~joy_data=0 -> buttons_buf filled with 0s
        // This means buttons_buf[15:12]==0 -> SNES detected
        joy_data = 1;
        // Reset the controller to start a new scan
        resetn = 0;
        repeat (5) @(posedge clk);
        resetn = 1;
        repeat (2000) @(posedge clk);

        $display("DUT buttons (SNES test) = 0x%03x", buttons);

        $display("Functional Coverage: %.1f%%", 0);
        $finish;
    end
endmodule

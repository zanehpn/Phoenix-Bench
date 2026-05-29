// Testbench for pulp-platform/pulp_soc PR#54
// Verifies that the lint_r_aux_i port of adbg_lintonly_top inside
// lint_jtag_wrap is tied to '0 (not left floating/X).
//
// Approach: We provide a stub for adbg_lintonly_top that captures the
// lint_r_aux_i input and exposes it via a global variable so the testbench
// can check its value after elaboration and a small simulation window.

// ---------------------------------------------------------------------------
// Stub: adbg_lintonly_top
// Mimics the port interface so lint_jtag_wrap can be compiled and elaborated.
// The key port under test is lint_r_aux_i.
// ---------------------------------------------------------------------------
module adbg_lintonly_top #(
    parameter ADDR_WIDTH = 32,
    parameter DATA_WIDTH = 32
) (
    input  logic                    tck_i,
    input  logic                    tdi_i,
    output logic                    tdo_o,
    input  logic                    trstn_i,

    input  logic                    shift_dr_i,
    input  logic                    pause_dr_i,
    input  logic                    update_dr_i,
    input  logic                    capture_dr_i,

    input  logic                    debug_select_i,

    input  logic                    clk_i,
    input  logic                    rstn_i,

    output logic                    lint_req_o,
    output logic [ADDR_WIDTH-1:0]   lint_add_o,
    output logic                    lint_wen_o,
    output logic [DATA_WIDTH-1:0]   lint_wdata_o,
    output logic [DATA_WIDTH/8-1:0] lint_be_o,
    output logic                    lint_aux_o,
    input  logic                    lint_gnt_i,
    input  logic                    lint_r_aux_i,   // PORT UNDER TEST
    input  logic                    lint_r_valid_i,
    input  logic [DATA_WIDTH-1:0]   lint_r_rdata_i,
    input  logic                    lint_r_opc_i
);

    // Drive outputs to safe defaults
    assign tdo_o       = 1'b0;
    assign lint_req_o  = 1'b0;
    assign lint_add_o  = '0;
    assign lint_wen_o  = 1'b0;
    assign lint_wdata_o = '0;
    assign lint_be_o   = '0;
    assign lint_aux_o  = 1'b0;

    // Expose lint_r_aux_i for testbench checking via hierarchical reference
    // (the testbench will read this via the instance path)

endmodule


// ---------------------------------------------------------------------------
// Testbench
// ---------------------------------------------------------------------------
module tb_lint_jtag_wrap;

    logic        clk;
    logic        rst_n;
    logic        tck, tdi, trstn, tdo;
    logic        shift_dr, pause_dr, update_dr, capture_dr;
    logic        lint_select;

    // Interface instance
    XBAR_TCDM_BUS jtag_lint_bus();

    // Drive the slave side of the bus so the master-side inputs are defined
    assign jtag_lint_bus.gnt     = 1'b0;
    assign jtag_lint_bus.r_valid = 1'b0;
    assign jtag_lint_bus.r_rdata = '0;
    assign jtag_lint_bus.r_opc   = 1'b0;

    // DUT
    lint_jtag_wrap #(
        .ADDRESS_WIDTH (32),
        .DATA_WIDTH    (32)
    ) dut (
        .tck_i            ( tck             ),
        .tdi_i            ( tdi             ),
        .trstn_i          ( trstn           ),
        .tdo_o            ( tdo             ),
        .shift_dr_i       ( shift_dr        ),
        .pause_dr_i       ( pause_dr        ),
        .update_dr_i      ( update_dr       ),
        .capture_dr_i     ( capture_dr      ),
        .lint_select_i    ( lint_select     ),
        .clk_i            ( clk             ),
        .rst_ni           ( rst_n           ),
        .jtag_lint_master ( jtag_lint_bus   )
    );

    // Clock generation
    initial clk = 0;
    always #5 clk = ~clk;

    // Patch-focused covergroup (PR#54: lint_r_aux_i tied to '0, r_opc added, default case)
    // The fix ties lint_r_aux_i to '0 instead of leaving it floating (X).
    // Also adds r_opc signal routing and default FSM case.
    wire lint_r_aux_val = dut.dbg_module_i.lint_r_aux_i;

    // [verilator-strip cg] covergroup cg_patch;
// [verilator-strip cg]       cp_lint_r_aux: coverpoint lint_r_aux_val {
// [verilator-strip cg]         bins tied_zero = {1'b0};
// [verilator-strip cg]         illegal_bins floating_x = {1'bx};
// [verilator-strip cg]       }
// [verilator-strip cg]       cp_rst_n: coverpoint rst_n {
// [verilator-strip cg]         bins active   = {1'b0};
// [verilator-strip cg]         bins released = {1'b1};
// [verilator-strip cg]       }
// [verilator-strip cg]       cp_trstn: coverpoint trstn {
// [verilator-strip cg]         bins active   = {1'b0};
// [verilator-strip cg]         bins released = {1'b1};
// [verilator-strip cg]       }
// [verilator-strip cg]       cp_lint_select: coverpoint lint_select {
// [verilator-strip cg]         bins deselected = {1'b0};
// [verilator-strip cg]         bins selected   = {1'b1};
// [verilator-strip cg]       }
// [verilator-strip cg]       cp_tdo: coverpoint tdo {
// [verilator-strip cg]         bins low  = {1'b0};
// [verilator-strip cg]       }
// [verilator-strip cg]       // Cross: lint_r_aux_i should be 0 regardless of reset state
// [verilator-strip cg]       cx_aux_reset: cross cp_lint_r_aux, cp_rst_n;
// [verilator-strip cg]       // Cross: lint_r_aux_i should be 0 regardless of trstn state
// [verilator-strip cg]       cx_aux_trstn: cross cp_lint_r_aux, cp_trstn;
// [verilator-strip cg]     endgroup

    // [verilator-strip cg-inst] cg_patch cg_inst = new();

    // Stimulus and checking
    initial begin
        // Initialize inputs
        rst_n      = 0;
        tck        = 0;
        tdi        = 0;
        trstn      = 0;
        shift_dr   = 0;
        pause_dr   = 0;
        update_dr  = 0;
        capture_dr = 0;
        lint_select = 0;

        // Sample during reset (rst_n=0, trstn=0)
        #10;
        /* [verilator-strip sample] */;

        // Release rst_n but keep trstn asserted
        rst_n = 1;
        #10;
        /* [verilator-strip sample] */;

        // Release trstn
        trstn = 1;
        #10;
        /* [verilator-strip sample] */;

        // -------------------------------------------------------------------
        // Check: lint_r_aux_i inside the DUT's dbg_module_i must be 0, not X
        // -------------------------------------------------------------------
        if (dut.dbg_module_i.lint_r_aux_i === 1'b0) begin
            $display("PASS: lint_r_aux_i is correctly tied to 0.");
        end else if (dut.dbg_module_i.lint_r_aux_i === 1'bx) begin
            $fatal(1, "FAIL: lint_r_aux_i is X (floating/unconnected).");
        end else begin
            $fatal(1, "FAIL: lint_r_aux_i has unexpected value: %b",
                     dut.dbg_module_i.lint_r_aux_i);
        end

        // Test with lint_select active
        lint_select = 1;
        #10;
        /* [verilator-strip sample] */;

        // Verify lint_r_aux_i still 0 with lint_select active
        if (dut.dbg_module_i.lint_r_aux_i === 1'b0) begin
            $display("PASS: lint_r_aux_i still 0 with lint_select active.");
        end else begin
            $fatal(1, "FAIL: lint_r_aux_i changed when lint_select active.");
        end

        // Test toggling JTAG signals
        shift_dr = 1;
        #10;
        /* [verilator-strip sample] */;
        shift_dr = 0;
        capture_dr = 1;
        #10;
        /* [verilator-strip sample] */;
        capture_dr = 0;
        update_dr = 1;
        #10;
        /* [verilator-strip sample] */;
        update_dr = 0;

        // Re-assert reset to test reset path again
        rst_n = 0;
        trstn = 0;
        #20;
        /* [verilator-strip sample] */;

        // Check during reset
        if (dut.dbg_module_i.lint_r_aux_i === 1'b0) begin
            $display("PASS: lint_r_aux_i still 0 during reset re-assertion.");
        end else begin
            $fatal(1, "FAIL: lint_r_aux_i not 0 during reset re-assertion.");
        end

        rst_n = 1;
        trstn = 1;
        #10;
        /* [verilator-strip sample] */;

        $display("Functional Coverage: %.1f%%", 0);
        #10;
        $finish;
    end

endmodule

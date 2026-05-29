module tb_if_stage_patch;

    // Clock + reset
    logic clk;
    logic rst_n;

    // IF stage I/O
    logic         req_i;
    logic         instr_gnt_i;
    logic         instr_rvalid_i;
    logic [31:0]  instr_rdata_i;
    logic         instr_bus_err_i;
    logic         pmp_err_if_i;
    logic         pmp_err_if_plus2_i;

    // Outputs of interest
    logic         instr_fetch_err_o;
    logic         instr_fetch_err_plus2_o;

    // IF stage produces address + instruction
    // To simplify testbench, we manually assign fetch_addr and fetch_rdata
    // using direct signal force.
    // (No icache / no prefetch buffer)
    // Parameters

    // Instantiate DUT with minimal config (no ICache, no branch predictor)
    ibex_if_stage #(
        .ICache(0),
        .BranchPredictor(0),
        .DummyInstructions(0),
        .PCIncrCheck(0),
        .ResetAll(1)
    ) dut (
        .clk_i(clk),
        .rst_ni(rst_n),

        .boot_addr_i(32'h0000_0000),
        .req_i(req_i),

        .instr_req_o(),
        .instr_addr_o(),
        .instr_gnt_i(instr_gnt_i),
        .instr_rvalid_i(instr_rvalid_i),
        .instr_rdata_i(instr_rdata_i),
        .instr_bus_err_i(instr_bus_err_i),
        .instr_intg_err_o(),

        .ic_tag_req_o(),
        .ic_tag_write_o(),
        .ic_tag_addr_o(),
        .ic_tag_wdata_o(),
        .ic_tag_rdata_i(),
        .ic_data_req_o(),
        .ic_data_write_o(),
        .ic_data_addr_o(),
        .ic_data_wdata_o(),
        .ic_data_rdata_i(),
        .ic_scr_key_valid_i(1'b0),
        .ic_scr_key_req_o(),

        .instr_valid_id_o(),
        .instr_new_id_o(),
        .instr_rdata_id_o(),
        .instr_rdata_alu_id_o(),
        .instr_rdata_c_id_o(),
        .instr_is_compressed_id_o(),
        .instr_bp_taken_o(),
        .instr_fetch_err_o(instr_fetch_err_o),
        .instr_fetch_err_plus2_o(instr_fetch_err_plus2_o),
        .illegal_c_insn_id_o(),
        .dummy_instr_id_o(),
        .pc_if_o(),
        .pc_id_o(),
        .pmp_err_if_i(pmp_err_if_i),
        .pmp_err_if_plus2_i(pmp_err_if_plus2_i),

        .instr_valid_clear_i(0),
        .pc_set_i(0),
        .pc_mux_i(ibex_pkg::PC_BOOT),
        .nt_branch_mispredict_i(0),
        .nt_branch_addr_i(0),
        .exc_pc_mux_i(ibex_pkg::EXC_PC_EXC),
        .exc_cause('0),
        .dummy_instr_en_i(0),
        .dummy_instr_mask_i(0),
        .dummy_instr_seed_en_i(0),
        .dummy_instr_seed_i(0),
        .icache_enable_i(0),
        .icache_inval_i(0),
        .icache_ecc_error_o(),

        .branch_target_ex_i(32'h0),

        .csr_mepc_i(32'h0),
        .csr_depc_i(32'h0),
        .csr_mtvec_i(32'h0),
        .csr_mtvec_init_o(),

        .id_in_ready_i(1'b1),

        .pc_mismatch_alert_o(),
        .if_busy_o()
    );

    // Clock generator
    always #5 clk = ~clk;

    // -------------------------
    //  Helper: Check function
    // -------------------------
    int fail_count = 0;
    int pass_count = 0;

    task check(string msg, bit exp);
        @(posedge clk);
        if (dut.if_instr_pmp_err !== exp) begin
            $fatal(1, "FAIL: %-20s expected=%0d got=%0d", msg, exp, dut.if_instr_pmp_err);
            fail_count++;
        end else begin
            $display("PASS: %-20s", msg);
            pass_count++;
        end
    endtask

    task check_err_plus2(string msg, bit exp);
        @(posedge clk);
        if (dut.if_instr_err_plus2 !== exp) begin
            $fatal(1, "FAIL: %-20s expected=%0d got=%0d", msg, exp, dut.if_instr_err_plus2);
            fail_count++;
        end else begin
            $display("PASS: %-20s", msg);
            pass_count++;
        end
    endtask

    // ----------------------------------------
    //               TEST FLOW
    // ----------------------------------------
    initial begin
        $display("\n=== IF PMP Patch Validation ===");

        clk = 0; rst_n = 0;

        req_i           = 1;
        instr_gnt_i     = 1;
        instr_rvalid_i  = 1;
        instr_rdata_i   = 32'h0000_0000;
        instr_bus_err_i = 0;

        pmp_err_if_i         = 0;
        pmp_err_if_plus2_i   = 0;

        repeat (5) @(posedge clk);
        rst_n = 1;

        // ----------------------------------------
        // Patch BUG trigger case:
        // if_instr_addr = 0x00000002   → bit1=1, bit2=0
        // ----------------------------------------
        force dut.if_instr_addr = 32'h0000_0002;
        force dut.instr_is_compressed = 0;  // non-compressed instruction
        force dut.fetch_err = 0;

        pmp_err_if_i        = 0;
        pmp_err_if_plus2_i  = 1;

        // With old code -> FAIL (returns 0)
        // With patched code -> PASS (returns 1)
        check("pmp_err_plus2 check", 1);
        check("pmp_err_plus2 check", 1);

        // ----------------------------------------
        // Additional coverage: addr[1]=0, compressed=0, pmp_err_plus2=1
        // ----------------------------------------
        force dut.if_instr_addr = 32'h0000_0000;
        force dut.instr_is_compressed = 0;
        force dut.fetch_err = 0;
        pmp_err_if_i        = 0;
        pmp_err_if_plus2_i  = 1;
        @(posedge clk);

        // ----------------------------------------
        // addr[1]=0, compressed=0, pmp_err_plus2=0
        // ----------------------------------------
        pmp_err_if_i        = 0;
        pmp_err_if_plus2_i  = 0;
        @(posedge clk);

        // ----------------------------------------
        // addr[1]=1, compressed=0, pmp_err_plus2=0
        // ----------------------------------------
        force dut.if_instr_addr = 32'h0000_0002;
        pmp_err_if_i        = 0;
        pmp_err_if_plus2_i  = 0;
        @(posedge clk);

        // ----------------------------------------
        // addr[1]=0, compressed=1, pmp_err_plus2=0
        // ----------------------------------------
        force dut.if_instr_addr = 32'h0000_0000;
        force dut.instr_is_compressed = 1;
        pmp_err_if_i        = 0;
        pmp_err_if_plus2_i  = 0;
        @(posedge clk);

        // ----------------------------------------
        // addr[1]=0, compressed=1, pmp_err_plus2=1
        // ----------------------------------------
        pmp_err_if_i        = 0;
        pmp_err_if_plus2_i  = 1;
        @(posedge clk);

        // ----------------------------------------
        // addr[1]=1, compressed=1, pmp_err_plus2=0
        // ----------------------------------------
        force dut.if_instr_addr = 32'h0000_0002;
        force dut.instr_is_compressed = 1;
        pmp_err_if_i        = 0;
        pmp_err_if_plus2_i  = 0;
        @(posedge clk);

        // ----------------------------------------
        // addr[1]=1, compressed=1, pmp_err_plus2=1
        // ----------------------------------------
        pmp_err_if_i        = 0;
        pmp_err_if_plus2_i  = 1;
        @(posedge clk);

        // ----------------------------------------
        // pmp_err_if=1 combinations for cx_pmp_errs cross
        // ----------------------------------------
        force dut.if_instr_addr = 32'h0000_0002;
        force dut.instr_is_compressed = 0;
        force dut.fetch_err = 0;
        pmp_err_if_i        = 1;
        pmp_err_if_plus2_i  = 0;
        @(posedge clk);

        pmp_err_if_i        = 1;
        pmp_err_if_plus2_i  = 1;
        @(posedge clk);

        release dut.if_instr_addr;
        release dut.instr_is_compressed;
        release dut.fetch_err;

        $display("Functional Coverage: %.1f%%", 0);
        if (fail_count > 0) begin
            $display("\nFAIL: %0d test(s) failed!", fail_count);
            $finish;
        end else begin
            $display("\nIF PMP patch PASS!");
            $finish;
        end
    end


  initial begin
    $dumpfile("tb_if_stage_patch.vcd");
    $dumpvars(0);
  end

  // ---------------------------------------------------------------
  // Patch-focused functional coverage
  // ---------------------------------------------------------------
  // Patch: if_instr_pmp_err and if_instr_err_plus2 now use
  //        if_instr_addr[1] instead of if_instr_addr[2]

  // [verilator-strip cg] covergroup cg_patch @(posedge clk);
// [verilator-strip cg]     cp_pmp_err_if: coverpoint pmp_err_if_i {
// [verilator-strip cg]       bins no_err = {1'b0};
// [verilator-strip cg]       bins err    = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_pmp_err_plus2: coverpoint pmp_err_if_plus2_i {
// [verilator-strip cg]       bins no_err = {1'b0};
// [verilator-strip cg]       bins err    = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_addr_bit1: coverpoint dut.if_instr_addr[1] {
// [verilator-strip cg]       bins lo = {1'b0};
// [verilator-strip cg]       bins hi = {1'b1};
// [verilator-strip cg]     }
// [verilator-strip cg]     cp_compressed: coverpoint dut.instr_is_compressed {
// [verilator-strip cg]       bins compressed     = {1'b1};
// [verilator-strip cg]       bins not_compressed = {1'b0};
// [verilator-strip cg]     }
// [verilator-strip cg]     // Cross: The patch-related condition - addr[1] & ~compressed & pmp_err_plus2
// [verilator-strip cg]     cx_pmp_plus2: cross cp_addr_bit1, cp_compressed, cp_pmp_err_plus2;
// [verilator-strip cg]     // Cross: primary PMP error with plus2
// [verilator-strip cg]     cx_pmp_errs: cross cp_pmp_err_if, cp_pmp_err_plus2;
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_patch cg_inst = new();

endmodule

module tb_ibex_cs_registers_icache_patch;

    // ---------------------------------------------------------------
    // Clock + reset
    // ---------------------------------------------------------------
    logic clk;
    logic rst_n;

    // ---------------------------------------------------------------
    // DUT signals under direct control
    // ---------------------------------------------------------------
    logic                 debug_mode_i;
    logic                 debug_mode_entering_i;

    // Output under test
    logic                 icache_enable_o;

    logic                 csr_access_i;
    logic [31:0]          csr_wdata_i;
    logic                 csr_op_en_i;
    ibex_pkg::csr_op_e    csr_op_i;
    ibex_pkg::csr_num_e   csr_addr_i;

    // Read-back data for CSR verification
    logic [31:0]          csr_rdata_o;

    // Unused ports tied-off
    logic cheri_pmode_i = 0;
    logic [31:0] hart_id_i = 0;

    // ---------------------------------------------------------------
    // Error tracking
    // ---------------------------------------------------------------
    int err_count = 0;
    int pass_count = 0;

    // ---------------------------------------------------------------
    // DUT instantiation
    // ---------------------------------------------------------------
    ibex_cs_registers #(
        .DbgTriggerEn      (0),
        .DbgHwBreakNum     (1),
        .DataIndTiming     (1'b0),
        .DummyInstructions (1'b0),
        .ShadowCSR         (1'b0),
        .ICache            (1'b1),   // ICache must be enabled for icache_enable field to exist
        .MHPMCounterNum    (10),
        .MHPMCounterWidth  (40),
        .PMPEnable         (0),
        .PMPGranularity    (0),
        .PMPNumRegions     (4),
        .RV32E             (0),
        .RV32M             (ibex_pkg::RV32MFast),
        .RV32B             (ibex_pkg::RV32BNone),
        .CHERIoTEn         (1'b1)
    ) dut (

        // Clock/reset
        .clk_i              (clk),
        .rst_ni             (rst_n),

        // CHERI + hart
        .cheri_pmode_i      (cheri_pmode_i),
        .hart_id_i          (hart_id_i),

        // Privilege
        .priv_mode_id_o     (),
        .priv_mode_lsu_o    (),
        .csr_mstatus_tw_o   (),

        // mtvec
        .csr_mtvec_o        (),
        .csr_mtvec_init_i   (1'b0),
        .boot_addr_i        (32'h00000000),

        // Main CSR interface
        .csr_access_i       (csr_access_i),
        .csr_addr_i         (csr_addr_i),
        .csr_wdata_i        (csr_wdata_i),
        .csr_op_i           (csr_op_i),
        .csr_op_en_i        (csr_op_en_i),
        .csr_rdata_o        (csr_rdata_o),

        // CHERI CSR (unused)
        .cheri_csr_access_i (1'b0),
        .cheri_csr_addr_i   (5'd0),
        .cheri_csr_wdata_i  (32'd0),
        .cheri_csr_wcap_i   ('0),
        .cheri_csr_op_i     ('0),
        .cheri_csr_op_en_i  (1'b0),
        .cheri_csr_set_mie_i(1'b0),
        .cheri_csr_clr_mie_i(1'b0),
        .cheri_csr_rdata_o  (),
        .cheri_csr_rcap_o   (),

        // Stack watermark (unused)
        .csr_mshwm_o        (),
        .csr_mshwmb_o       (),
        .csr_mshwm_set_i    (1'b0),
        .csr_mshwm_new_i    (32'd0),

        // IRQ
        .irq_software_i     (1'b0),
        .irq_timer_i        (1'b0),
        .irq_external_i     (1'b0),
        .irq_fast_i         (15'd0),
        .nmi_mode_i         (1'b0),
        .irq_pending_o      (),
        .irqs_o             (),
        .csr_mstatus_mie_o  (),
        .csr_mepc_o         (),

        // PMP (unused)
        .csr_pmp_cfg_o      (),
        .csr_pmp_addr_o     (),
        .csr_pmp_mseccfg_o  (),

        // Debug signals
        .debug_mode_i         (debug_mode_i),
        .debug_mode_entering_i(debug_mode_entering_i),
        .debug_cause_i        (ibex_pkg::DBG_CAUSE_EBREAK),
        .debug_csr_save_i     (1'b0),
        .csr_depc_o           (),
        .debug_single_step_o  (),
        .debug_ebreakm_o      (),
        .debug_ebreaku_o      (),
        .trigger_match_o      (),

        // PCs
        .pc_if_i            (32'd0),
        .pc_id_i            (32'd0),
        .pc_wb_i            (32'd0),

        // CPU control outputs
        .data_ind_timing_o  (),
        .dummy_instr_en_o   (),
        .dummy_instr_mask_o (),
        .dummy_instr_seed_en_o (),
        .dummy_instr_seed_o (),
        .icache_enable_o    (icache_enable_o),   // key signal under test
        .csr_shadow_err_o   (),

        // Exception control
        .csr_save_if_i      (1'b0),
        .csr_save_id_i      (1'b0),
        .csr_save_wb_i      (1'b0),
        .csr_restore_mret_i (1'b0),
        .csr_restore_dret_i (1'b0),
        .csr_save_cause_i   (1'b0),
        .csr_mepcc_clrtag_i (1'b0),
        .csr_mcause_i       ('0),
        .csr_mtval_i        (32'd0),
        .illegal_csr_insn_o (),
        .double_fault_seen_o(),

        // Performance counters (unused)
        .instr_ret_i                 (1'b0),
        .instr_ret_compressed_i      (1'b0),
        .instr_ret_spec_i            (1'b0),
        .instr_ret_compressed_spec_i (1'b0),
        .iside_wait_i                (1'b0),
        .jump_i                      (1'b0),
        .branch_i                    (1'b0),
        .branch_taken_i              (1'b0),
        .mem_load_i                  (1'b0),
        .mem_store_i                 (1'b0),
        .dside_wait_i                (1'b0),
        .mul_wait_i                  (1'b0),
        .div_wait_i                  (1'b0),

        // CHERI branch + PCC
        .cheri_branch_req_i    (1'b0),
        .cheri_branch_target_i (32'd0),
        .pcc_cap_i             ('0),
        .pcc_cap_o             (),

        // Debug fault
        .csr_dbg_tclr_fault_o  (),
        .cheri_fatal_err_o     ()
    );

    // ---------------------------------------------------------------
    // Clock generation: 100 MHz (10 ns period)
    // ---------------------------------------------------------------
    always #5 clk = ~clk;

    // ---------------------------------------------------------------
    // Task: Write to CSR_CPUCTRL using a specified CSR operation
    //   cpu_ctrl_t is packed {double_fault_seen, sync_exc_seen,
    //     dummy_instr_mask[2:0], dummy_instr_en, data_ind_timing,
    //     icache_enable}
    //   => icache_enable is bit 0
    // ---------------------------------------------------------------
    task write_cpuctrl_op(logic [31:0] wdata, ibex_pkg::csr_op_e op);
        begin
            @(posedge clk);
            csr_access_i = 1;
            csr_op_en_i  = 1;
            csr_op_i     = op;
            csr_addr_i   = ibex_pkg::CSR_CPUCTRL;
            csr_wdata_i  = wdata;
            @(posedge clk);
            csr_access_i = 0;
            csr_op_en_i  = 0;
            csr_wdata_i  = 0;
        end
    endtask

    task write_cpuctrl(bit ic_en);
        write_cpuctrl_op({31'b0, ic_en}, ibex_pkg::CSR_OP_WRITE);
    endtask

    // ---------------------------------------------------------------
    // Task: Read CSR_CPUCTRL and return the read data
    // ---------------------------------------------------------------
    task read_cpuctrl(output logic [31:0] rdata);
        begin
            @(posedge clk);
            csr_access_i = 1;
            csr_op_en_i  = 0;           // read-only, no write-enable
            csr_op_i     = ibex_pkg::CSR_OP_READ;
            csr_addr_i   = ibex_pkg::CSR_CPUCTRL;
            csr_wdata_i  = 32'd0;
            @(posedge clk);
            rdata = csr_rdata_o;
            csr_access_i = 0;
        end
    endtask

    // ---------------------------------------------------------------
    // Task: Assert icache_enable_o matches expected value
    // ---------------------------------------------------------------
    task check(string msg,
               bit dbg,
               bit dbg_enter,
               bit expected);

        debug_mode_i          = dbg;
        debug_mode_entering_i = dbg_enter;
        @(posedge clk);
        // Allow combinational output to settle
        #1;

        if (icache_enable_o !== expected) begin
            $display("FAIL: %-50s  debug_mode=%0b  debug_entering=%0b  expected=%0b  got=%0b",
                     msg, dbg, dbg_enter, expected, icache_enable_o);
            err_count++;
        end else begin
            $display("PASS: %-50s  debug_mode=%0b  debug_entering=%0b  icache_enable=%0b",
                     msg, dbg, dbg_enter, icache_enable_o);
            pass_count++;
        end
    endtask

    // ---------------------------------------------------------------
    // Task: Check icache_enable_o without changing debug signals
    // ---------------------------------------------------------------
    task check_no_set(string msg, bit expected);
        @(posedge clk);
        #1;
        if (icache_enable_o !== expected) begin
            $display("FAIL: %-50s  expected=%0b  got=%0b", msg, expected, icache_enable_o);
            err_count++;
        end else begin
            $display("PASS: %-50s  icache_enable=%0b", msg, icache_enable_o);
            pass_count++;
        end
    endtask

    // ---------------------------------------------------------------
    // Task: Apply reset
    // ---------------------------------------------------------------
    task do_reset();
        begin
            rst_n = 0;
            debug_mode_i          = 0;
            debug_mode_entering_i = 0;
            csr_access_i          = 0;
            csr_op_en_i           = 0;
            csr_wdata_i           = 0;
            repeat (5) @(posedge clk);
            rst_n = 1;
            repeat (2) @(posedge clk);
        end
    endtask

    // ---------------------------------------------------------------
    // Patch-focused coverage
    // ---------------------------------------------------------------
    covergroup cg_patch;
      cp_debug_mode:     coverpoint debug_mode_i;
      cp_debug_entering: coverpoint debug_mode_entering_i;
      cp_icache_enable:  coverpoint icache_enable_o;
      cx_debug_icache:   cross cp_debug_mode, cp_debug_entering, cp_icache_enable {
        // When debug_mode or debug_entering is active, icache_enable_o is always forced to 0
        ignore_bins unreachable_debug_ic1 = binsof(cp_debug_mode) intersect {1} &&
                                            binsof(cp_icache_enable) intersect {1};
        ignore_bins unreachable_enter_ic1 = binsof(cp_debug_entering) intersect {1} &&
                                            binsof(cp_icache_enable) intersect {1};
      }
    endgroup

    cg_patch cg_inst = new();

    always @(posedge clk) begin
      if (rst_n) cg_inst.sample();
    end

    // ---------------------------------------------------------------
    // Main test sequence
    // ---------------------------------------------------------------
    initial begin
        $display("\n=== Ibex ICache Debug-Mode Disable Patch Validation TB ===\n");

        clk = 0;
        do_reset();

        // =============================================================
        // TEST GROUP 1: Basic icache_enable output after reset
        // =============================================================
        $display("--- Test Group 1: Post-reset defaults ---");

        // After reset cpuctrl_q should be all-zero, so icache_enable = 0
        check("T1.1: reset default, no debug",        0, 0, 0);
        check("T1.2: reset default, debug_mode=1",    1, 0, 0);
        check("T1.3: reset default, debug_entering=1",0, 1, 0);
        check("T1.4: reset default, both debug=1",    1, 1, 0);

        // =============================================================
        // TEST GROUP 2: Enable icache, then test all debug combinations
        // =============================================================
        $display("\n--- Test Group 2: icache enabled, debug signal combinations ---");

        // Turn off debug signals before writing CSR
        debug_mode_i          = 0;
        debug_mode_entering_i = 0;
        @(posedge clk);

        write_cpuctrl(1);

        // With icache_enable CSR bit = 1:
        //   icache_enable_o = 1 & ~(debug_mode | debug_entering)
        check("T2.1: icache=1, no debug",             0, 0, 1);
        check("T2.2: icache=1, debug_mode=1",         1, 0, 0);
        check("T2.3: icache=1, debug_entering=1",     0, 1, 0);
        check("T2.4: icache=1, both debug=1",         1, 1, 0);

        // =============================================================
        // TEST GROUP 3: Disable icache via CSR, verify stays 0
        // =============================================================
        $display("\n--- Test Group 3: icache disabled via CSR ---");

        debug_mode_i          = 0;
        debug_mode_entering_i = 0;
        @(posedge clk);

        write_cpuctrl(0);

        check("T3.1: icache=0, no debug",             0, 0, 0);
        check("T3.2: icache=0, debug_mode=1",         1, 0, 0);
        check("T3.3: icache=0, debug_entering=1",     0, 1, 0);
        check("T3.4: icache=0, both debug=1",         1, 1, 0);

        // =============================================================
        // TEST GROUP 4: Transition sequences (entering -> active -> exit)
        // =============================================================
        $display("\n--- Test Group 4: Debug entry/exit transitions ---");

        // Re-enable icache
        debug_mode_i          = 0;
        debug_mode_entering_i = 0;
        @(posedge clk);
        write_cpuctrl(1);

        // 4a: Normal -> Entering debug -> In debug -> Exit debug
        check("T4.1: pre-entry, normal mode",         0, 0, 1);
        check("T4.2: entering debug (pulse)",          0, 1, 0);
        check("T4.3: entering + mode set same cycle",  1, 1, 0);
        check("T4.4: in debug mode (entering done)",   1, 0, 0);
        check("T4.5: exit debug, back to normal",      0, 0, 1);

        // 4b: Re-enter debug to make sure icache disables again
        check("T4.6: re-enter debug",                  1, 0, 0);
        check("T4.7: exit debug again",                0, 0, 1);

        // =============================================================
        // TEST GROUP 5: Rapid toggling of debug signals
        // =============================================================
        $display("\n--- Test Group 5: Rapid toggling ---");

        // icache still enabled from above
        begin
            int i;
            for (i = 0; i < 8; i++) begin
                automatic bit dm  = i[0];
                automatic bit de  = i[1];
                automatic bit exp = ~(dm | de);  // icache_en=1, so result = ~(dm|de)
                check($sformatf("T5.%0d: toggle dm=%0b de=%0b", i, dm, de),
                      dm, de, exp);
            end
        end

        // =============================================================
        // TEST GROUP 6: CSR write while in debug mode
        //   Verify that writing icache_enable=1 via CSR while in debug
        //   mode still results in icache_enable_o = 0 (masked)
        // =============================================================
        $display("\n--- Test Group 6: CSR write during debug mode ---");

        debug_mode_i          = 1;
        debug_mode_entering_i = 0;
        @(posedge clk);

        // Write icache_enable = 1 while debug_mode is active
        write_cpuctrl(1);
        check("T6.1: CSR write ic=1 during debug",    1, 0, 0);

        // Now leave debug -- the CSR bit should still be set,
        // so icache_enable_o should become 1
        check("T6.2: leave debug after CSR write",    0, 0, 1);

        // =============================================================
        // TEST GROUP 7: CSR write icache_enable=0 during debug,
        //   then leave debug -> should stay 0
        // =============================================================
        $display("\n--- Test Group 7: CSR clear during debug mode ---");

        debug_mode_i          = 1;
        debug_mode_entering_i = 0;
        @(posedge clk);

        write_cpuctrl(0);
        check("T7.1: CSR write ic=0 during debug",    1, 0, 0);
        check("T7.2: leave debug after ic cleared",    0, 0, 0);

        // =============================================================
        // TEST GROUP 8: debug_mode_entering_i pulse width = 1 cycle
        //   Verify single-cycle pulse correctly suppresses icache
        // =============================================================
        $display("\n--- Test Group 8: Single-cycle entering pulse ---");

        // Re-enable icache
        debug_mode_i          = 0;
        debug_mode_entering_i = 0;
        @(posedge clk);
        write_cpuctrl(1);

        // Verify enabled
        check("T8.1: baseline enabled",               0, 0, 1);

        // Single-cycle pulse on debug_mode_entering_i
        debug_mode_entering_i = 1;
        @(posedge clk);
        #1;
        if (icache_enable_o !== 1'b0) begin
            $display("FAIL: T8.2: entering pulse should suppress icache, got %0b", icache_enable_o);
            err_count++;
        end else begin
            $display("PASS: T8.2: entering pulse suppresses icache");
            pass_count++;
        end

        // Deassert entering, assert debug_mode (simulating controller behaviour)
        debug_mode_entering_i = 0;
        debug_mode_i          = 1;
        @(posedge clk);
        #1;
        if (icache_enable_o !== 1'b0) begin
            $display("FAIL: T8.3: in debug mode, icache should be 0, got %0b", icache_enable_o);
            err_count++;
        end else begin
            $display("PASS: T8.3: debug_mode keeps icache suppressed after entering pulse");
            pass_count++;
        end

        // Leave debug
        debug_mode_i = 0;
        @(posedge clk);
        #1;
        if (icache_enable_o !== 1'b1) begin
            $display("FAIL: T8.4: after debug exit, icache should be 1, got %0b", icache_enable_o);
            err_count++;
        end else begin
            $display("PASS: T8.4: icache re-enabled after debug exit");
            pass_count++;
        end

        // =============================================================
        // TEST GROUP 9: Reset during debug mode
        //   Verify reset clears everything properly
        // =============================================================
        $display("\n--- Test Group 9: Reset during debug mode ---");

        debug_mode_i          = 1;
        debug_mode_entering_i = 0;
        @(posedge clk);
        write_cpuctrl(1);
        // icache CSR bit = 1 but debug masks it
        check("T9.1: in debug before reset",          1, 0, 0);

        // Apply reset while in debug mode
        do_reset();

        // After reset, cpuctrl should be cleared, debug inputs cleared by do_reset
        check("T9.2: after reset, no debug",          0, 0, 0);
        check("T9.3: after reset, debug_mode=1",      1, 0, 0);

        // Re-enable icache after reset
        debug_mode_i          = 0;
        debug_mode_entering_i = 0;
        @(posedge clk);
        write_cpuctrl(1);
        check("T9.4: re-enabled after reset",         0, 0, 1);

        // =============================================================
        // TEST GROUP 10: Combinational path verification
        //   icache_enable_o should respond to debug signals within the
        //   same cycle (combinational, not registered)
        // =============================================================
        $display("\n--- Test Group 10: Combinational response ---");

        // icache CSR bit = 1 from above, no debug
        debug_mode_i          = 0;
        debug_mode_entering_i = 0;
        @(posedge clk);
        #1;
        if (icache_enable_o !== 1'b1) begin
            $display("FAIL: T10.1: combinational baseline should be 1");
            err_count++;
        end else begin
            $display("PASS: T10.1: combinational baseline = 1");
            pass_count++;
        end

        // Mid-cycle: assert debug_mode, check combinational response
        debug_mode_i = 1;
        #1;
        if (icache_enable_o !== 1'b0) begin
            $display("FAIL: T10.2: mid-cycle debug_mode assertion should suppress icache");
            err_count++;
        end else begin
            $display("PASS: T10.2: mid-cycle debug_mode suppresses icache combinationally");
            pass_count++;
        end

        // Mid-cycle: deassert debug_mode, assert entering
        debug_mode_i          = 0;
        debug_mode_entering_i = 1;
        #1;
        if (icache_enable_o !== 1'b0) begin
            $display("FAIL: T10.3: mid-cycle entering assertion should suppress icache");
            err_count++;
        end else begin
            $display("PASS: T10.3: mid-cycle entering suppresses icache combinationally");
            pass_count++;
        end

        // Clear all
        debug_mode_i          = 0;
        debug_mode_entering_i = 0;
        #1;
        if (icache_enable_o !== 1'b1) begin
            $display("FAIL: T10.4: clearing debug signals restores icache combinationally");
            err_count++;
        end else begin
            $display("PASS: T10.4: clearing debug signals restores icache immediately");
            pass_count++;
        end

        // =============================================================
        // TEST GROUP 11: Sustained debug mode over multiple cycles
        // =============================================================
        $display("\n--- Test Group 11: Sustained debug mode ---");

        debug_mode_i          = 1;
        debug_mode_entering_i = 0;
        repeat (10) begin
            @(posedge clk);
            #1;
            if (icache_enable_o !== 1'b0) begin
                $display("FAIL: T11: icache should stay 0 during sustained debug mode");
                err_count++;
            end
        end
        $display("PASS: T11: icache stayed 0 for 10 cycles of sustained debug mode");
        pass_count++;

        // Exit debug
        debug_mode_i = 0;
        @(posedge clk);
        #1;
        if (icache_enable_o !== 1'b1) begin
            $display("FAIL: T11.exit: icache should re-enable after sustained debug");
            err_count++;
        end else begin
            $display("PASS: T11.exit: icache re-enables after sustained debug");
            pass_count++;
        end

        // =============================================================
        // TEST GROUP 12: Write other CPUCTRL fields, verify icache_enable
        //   is unaffected by other bits in the register
        // =============================================================
        $display("\n--- Test Group 12: Other CPUCTRL fields do not affect icache ---");

        debug_mode_i          = 0;
        debug_mode_entering_i = 0;
        @(posedge clk);

        // Write CPUCTRL with icache_enable=1 and some other bits set
        // cpu_ctrl_t = {double_fault_seen, sync_exc_seen, dummy_instr_mask[2:0],
        //               dummy_instr_en, data_ind_timing, icache_enable}
        // Bits: [7]=double_fault  [6]=sync_exc  [5:3]=dummy_mask  [2]=dummy_en
        //       [1]=data_ind_timing  [0]=icache_enable
        @(posedge clk);
        csr_access_i = 1;
        csr_op_en_i  = 1;
        csr_op_i     = ibex_pkg::CSR_OP_WRITE;
        csr_addr_i   = ibex_pkg::CSR_CPUCTRL;
        csr_wdata_i  = 32'hFF;  // all lower 8 bits set
        @(posedge clk);
        csr_access_i = 0;
        csr_op_en_i  = 0;
        csr_wdata_i  = 0;

        check("T12.1: all CPUCTRL bits set, no debug", 0, 0, 1);
        check("T12.2: all CPUCTRL bits set, debug=1",  1, 0, 0);

        // Now write with only icache_enable=0, other bits set
        @(posedge clk);
        csr_access_i = 1;
        csr_op_en_i  = 1;
        csr_op_i     = ibex_pkg::CSR_OP_WRITE;
        csr_addr_i   = ibex_pkg::CSR_CPUCTRL;
        csr_wdata_i  = 32'hFE;  // bit 0 = 0
        @(posedge clk);
        csr_access_i = 0;
        csr_op_en_i  = 0;
        csr_wdata_i  = 0;

        check("T12.3: ic=0, other bits set, no debug", 0, 0, 0);
        check("T12.4: ic=0, other bits set, debug=1",  1, 0, 0);

        // =============================================================
        // TEST GROUP 13: CSR SET and CLEAR operations
        //   Verify icache_enable bit can be manipulated via SET/CLEAR
        //   and debug masking still applies
        // =============================================================
        $display("\n--- Test Group 13: CSR SET and CLEAR operations ---");

        debug_mode_i          = 0;
        debug_mode_entering_i = 0;
        @(posedge clk);

        // Start with icache_enable=0
        write_cpuctrl(0);
        check("T13.1: baseline ic=0",                 0, 0, 0);

        // Use CSR_OP_SET to set bit 0 (icache_enable)
        write_cpuctrl_op(32'h01, ibex_pkg::CSR_OP_SET);
        check("T13.2: SET bit0, no debug",             0, 0, 1);
        check("T13.3: SET bit0, debug_mode=1",         1, 0, 0);

        // Use CSR_OP_CLEAR to clear bit 0
        debug_mode_i          = 0;
        debug_mode_entering_i = 0;
        @(posedge clk);
        write_cpuctrl_op(32'h01, ibex_pkg::CSR_OP_CLEAR);
        check("T13.4: CLEAR bit0, no debug",           0, 0, 0);

        // SET bit 0 again, verify entering masks it
        write_cpuctrl_op(32'h01, ibex_pkg::CSR_OP_SET);
        check("T13.5: SET bit0, entering=1",           0, 1, 0);

        // Use CSR_OP_SET with all bits -- icache still masked
        write_cpuctrl_op(32'hFFFFFFFF, ibex_pkg::CSR_OP_SET);
        check("T13.6: SET all, debug=1",               1, 0, 0);
        check("T13.7: SET all, no debug",              0, 0, 1);

        // Use CSR_OP_CLEAR to clear everything, then verify
        write_cpuctrl_op(32'hFFFFFFFF, ibex_pkg::CSR_OP_CLEAR);
        check("T13.8: CLEAR all, no debug",            0, 0, 0);

        // =============================================================
        // TEST GROUP 14: Read-back verification
        //   The CSR read should reflect the stored bit value,
        //   NOT the masked output. The debug masking only
        //   affects icache_enable_o, not the register content.
        // =============================================================
        $display("\n--- Test Group 14: CSR read-back verification ---");
        begin
            logic [31:0] rdata;

            // Set icache_enable=1
            debug_mode_i          = 0;
            debug_mode_entering_i = 0;
            @(posedge clk);
            write_cpuctrl(1);

            // Read while NOT in debug mode
            read_cpuctrl(rdata);
            if (rdata[0] !== 1'b1) begin
                $display("FAIL: T14.1: CSR read ic_en bit should be 1, got %0b", rdata[0]);
                err_count++;
            end else begin
                $display("PASS: T14.1: CSR read returns ic_en=1 (no debug)");
                pass_count++;
            end

            // Read while IN debug mode -- CSR stored value should still be 1
            // (debug masking only affects icache_enable_o output, not the register)
            debug_mode_i = 1;
            debug_mode_entering_i = 0;
            @(posedge clk);
            read_cpuctrl(rdata);
            if (rdata[0] !== 1'b1) begin
                $display("FAIL: T14.2: CSR read ic_en bit should be 1 even in debug, got %0b", rdata[0]);
                err_count++;
            end else begin
                $display("PASS: T14.2: CSR read returns ic_en=1 during debug (stored value intact)");
                pass_count++;
            end

            // Verify icache_enable_o is still masked
            #1;
            if (icache_enable_o !== 1'b0) begin
                $display("FAIL: T14.3: icache_enable_o should be 0 in debug despite CSR=1");
                err_count++;
            end else begin
                $display("PASS: T14.3: icache_enable_o masked to 0 even though CSR bit=1");
                pass_count++;
            end

            // Read while entering debug
            debug_mode_i = 0;
            debug_mode_entering_i = 1;
            @(posedge clk);
            read_cpuctrl(rdata);
            if (rdata[0] !== 1'b1) begin
                $display("FAIL: T14.4: CSR read ic_en should be 1 during entering, got %0b", rdata[0]);
                err_count++;
            end else begin
                $display("PASS: T14.4: CSR read returns ic_en=1 during entering (stored value intact)");
                pass_count++;
            end

            // Write ic=0, read back
            debug_mode_i = 0;
            debug_mode_entering_i = 0;
            @(posedge clk);
            write_cpuctrl(0);
            read_cpuctrl(rdata);
            if (rdata[0] !== 1'b0) begin
                $display("FAIL: T14.5: CSR read after clearing ic should be 0, got %0b", rdata[0]);
                err_count++;
            end else begin
                $display("PASS: T14.5: CSR read returns ic_en=0 after clearing");
                pass_count++;
            end
        end

        // =============================================================
        // TEST GROUP 15: Concurrent CSR write and debug_mode_entering_i
        //   Write icache_enable=1 on the same cycle entering goes high.
        //   The output should be masked but the CSR value should take.
        // =============================================================
        $display("\n--- Test Group 15: CSR write concurrent with debug entering ---");
        begin
            logic [31:0] rdata;

            // Start with ic=0
            debug_mode_i          = 0;
            debug_mode_entering_i = 0;
            @(posedge clk);
            write_cpuctrl(0);

            // Now do a CSR write of ic=1 while asserting debug_mode_entering
            @(posedge clk);
            csr_access_i          = 1;
            csr_op_en_i           = 1;
            csr_op_i              = ibex_pkg::CSR_OP_WRITE;
            csr_addr_i            = ibex_pkg::CSR_CPUCTRL;
            csr_wdata_i           = 32'h01;
            debug_mode_entering_i = 1;
            @(posedge clk);
            csr_access_i          = 0;
            csr_op_en_i           = 0;
            csr_wdata_i           = 0;

            // Entering still asserted -- output should be 0
            #1;
            if (icache_enable_o !== 1'b0) begin
                $display("FAIL: T15.1: output should be 0 during entering+CSR write");
                err_count++;
            end else begin
                $display("PASS: T15.1: output masked during concurrent CSR write and entering");
                pass_count++;
            end

            // Transition to debug mode
            debug_mode_entering_i = 0;
            debug_mode_i          = 1;
            @(posedge clk);
            #1;
            if (icache_enable_o !== 1'b0) begin
                $display("FAIL: T15.2: output should be 0 in debug mode");
                err_count++;
            end else begin
                $display("PASS: T15.2: output stays masked in debug mode");
                pass_count++;
            end

            // Exit debug -- CSR write should have taken effect
            debug_mode_i = 0;
            @(posedge clk);
            #1;
            if (icache_enable_o !== 1'b1) begin
                $display("FAIL: T15.3: after debug exit, CSR write should have taken effect");
                err_count++;
            end else begin
                $display("PASS: T15.3: CSR write persisted through debug, output now 1");
                pass_count++;
            end

            // Double-check stored value
            read_cpuctrl(rdata);
            if (rdata[0] !== 1'b1) begin
                $display("FAIL: T15.4: stored CSR value should be 1 after concurrent write");
                err_count++;
            end else begin
                $display("PASS: T15.4: stored CSR value correct after concurrent write");
                pass_count++;
            end
        end

        // =============================================================
        // TEST GROUP 16: Multiple debug entry/exit cycles
        //   Stress test: repeatedly enter and exit debug mode, verifying
        //   icache correctly disables and re-enables each time
        // =============================================================
        $display("\n--- Test Group 16: Multiple debug entry/exit cycles ---");

        debug_mode_i          = 0;
        debug_mode_entering_i = 0;
        @(posedge clk);
        write_cpuctrl(1);

        begin
            int cycle_errors = 0;
            for (int i = 0; i < 20; i++) begin
                // Enter debug: entering pulse
                debug_mode_entering_i = 1;
                @(posedge clk);
                #1;
                if (icache_enable_o !== 1'b0) cycle_errors++;

                // In debug mode
                debug_mode_entering_i = 0;
                debug_mode_i          = 1;
                @(posedge clk);
                #1;
                if (icache_enable_o !== 1'b0) cycle_errors++;

                // Stay in debug for a variable number of cycles
                repeat (i % 5) begin
                    @(posedge clk);
                    #1;
                    if (icache_enable_o !== 1'b0) cycle_errors++;
                end

                // Exit debug
                debug_mode_i = 0;
                @(posedge clk);
                #1;
                if (icache_enable_o !== 1'b1) cycle_errors++;
            end

            if (cycle_errors == 0) begin
                $display("PASS: T16: 20 debug entry/exit cycles all correct");
                pass_count++;
            end else begin
                $display("FAIL: T16: %0d errors during 20 entry/exit cycles", cycle_errors);
                err_count++;
            end
        end

        // =============================================================
        // TEST GROUP 17: Reset with debug_mode_entering_i asserted
        //   Verify that asserting entering during reset and releasing
        //   afterward results in correct behavior
        // =============================================================
        $display("\n--- Test Group 17: Reset with entering asserted ---");

        // Set up icache enabled, then reset with entering high
        debug_mode_i          = 0;
        debug_mode_entering_i = 0;
        @(posedge clk);
        write_cpuctrl(1);
        check("T17.1: ic=1, baseline",                0, 0, 1);

        // Assert entering, then reset
        debug_mode_entering_i = 1;
        rst_n = 0;
        repeat (5) @(posedge clk);
        rst_n = 1;
        // Keep entering asserted after reset
        repeat (2) @(posedge clk);
        #1;
        // CSR is cleared by reset, so icache_enable_o = 0 regardless
        if (icache_enable_o !== 1'b0) begin
            $display("FAIL: T17.2: post-reset with entering=1, ic should be 0");
            err_count++;
        end else begin
            $display("PASS: T17.2: post-reset with entering=1, ic correctly 0");
            pass_count++;
        end

        // Deassert entering
        debug_mode_entering_i = 0;
        @(posedge clk);
        #1;
        // CSR still 0 from reset
        if (icache_enable_o !== 1'b0) begin
            $display("FAIL: T17.3: post-reset, entering deasserted, ic should be 0 (CSR cleared)");
            err_count++;
        end else begin
            $display("PASS: T17.3: post-reset, entering deasserted, CSR cleared so ic=0");
            pass_count++;
        end

        // =============================================================
        // TEST GROUP 18: Back-to-back CSR writes with debug toggling
        //   Write ic=1, immediately write ic=0 while debug toggles
        // =============================================================
        $display("\n--- Test Group 18: Back-to-back CSR writes with debug toggle ---");

        debug_mode_i          = 0;
        debug_mode_entering_i = 0;
        @(posedge clk);

        // Write ic=1
        write_cpuctrl(1);
        check("T18.1: after write ic=1, no debug",    0, 0, 1);

        // Enter debug and immediately write ic=0
        debug_mode_i = 1;
        @(posedge clk);
        write_cpuctrl(0);
        check("T18.2: wrote ic=0 in debug",           1, 0, 0);

        // Exit debug -- ic should be 0 because we cleared it
        check("T18.3: exit debug, ic should be 0",    0, 0, 0);

        // Write ic=1 in debug, then write ic=0 still in debug
        debug_mode_i = 1;
        @(posedge clk);
        write_cpuctrl(1);
        write_cpuctrl(0);
        check("T18.4: two writes in debug, last=0",   1, 0, 0);
        check("T18.5: exit debug, last write was 0",  0, 0, 0);

        // Write ic=0 in debug, then write ic=1 still in debug
        debug_mode_i = 1;
        @(posedge clk);
        write_cpuctrl(0);
        write_cpuctrl(1);
        check("T18.6: two writes in debug, last=1",   1, 0, 0);
        check("T18.7: exit debug, last write was 1",  0, 0, 1);

        // =============================================================
        // TEST GROUP 19: Glitch-like debug pulses (sub-cycle)
        //   Verify even very short combinational assertions of debug
        //   signals cause the output to go low
        // =============================================================
        $display("\n--- Test Group 19: Sub-cycle debug signal glitches ---");

        debug_mode_i          = 0;
        debug_mode_entering_i = 0;
        @(posedge clk);
        // Make sure ic is enabled
        write_cpuctrl(1);
        @(posedge clk);
        #1;

        // Verify baseline
        if (icache_enable_o !== 1'b1) begin
            $display("FAIL: T19.1: baseline should be 1");
            err_count++;
        end else begin
            $display("PASS: T19.1: baseline is 1");
            pass_count++;
        end

        // Short pulse on debug_mode_i
        debug_mode_i = 1;
        #1;
        if (icache_enable_o !== 1'b0) begin
            $display("FAIL: T19.2: short debug_mode pulse should suppress icache");
            err_count++;
        end else begin
            $display("PASS: T19.2: short debug_mode pulse suppresses icache");
            pass_count++;
        end
        debug_mode_i = 0;
        #1;
        if (icache_enable_o !== 1'b1) begin
            $display("FAIL: T19.3: icache should restore after debug_mode deassert");
            err_count++;
        end else begin
            $display("PASS: T19.3: icache restores after debug_mode deassert");
            pass_count++;
        end

        // Short pulse on debug_mode_entering_i
        debug_mode_entering_i = 1;
        #1;
        if (icache_enable_o !== 1'b0) begin
            $display("FAIL: T19.4: short entering pulse should suppress icache");
            err_count++;
        end else begin
            $display("PASS: T19.4: short entering pulse suppresses icache");
            pass_count++;
        end
        debug_mode_entering_i = 0;
        #1;
        if (icache_enable_o !== 1'b1) begin
            $display("FAIL: T19.5: icache should restore after entering deassert");
            err_count++;
        end else begin
            $display("PASS: T19.5: icache restores after entering deassert");
            pass_count++;
        end

        // Both simultaneously
        debug_mode_i          = 1;
        debug_mode_entering_i = 1;
        #1;
        if (icache_enable_o !== 1'b0) begin
            $display("FAIL: T19.6: both signals should suppress icache");
            err_count++;
        end else begin
            $display("PASS: T19.6: both signals suppress icache");
            pass_count++;
        end
        // Deassert only one
        debug_mode_i = 0;
        #1;
        if (icache_enable_o !== 1'b0) begin
            $display("FAIL: T19.7: entering still asserted, icache should remain 0");
            err_count++;
        end else begin
            $display("PASS: T19.7: entering still asserted, icache stays 0");
            pass_count++;
        end
        debug_mode_entering_i = 0;
        #1;
        if (icache_enable_o !== 1'b1) begin
            $display("FAIL: T19.8: both deasserted, icache should be 1");
            err_count++;
        end else begin
            $display("PASS: T19.8: both deasserted, icache restored");
            pass_count++;
        end

        // =============================================================
        // TEST GROUP 20: CSR SET/CLEAR during debug mode with read-back
        //   Verify CSR SET/CLEAR operations work correctly while debug
        //   is active, and that the stored value is correctly preserved
        // =============================================================
        $display("\n--- Test Group 20: CSR SET/CLEAR during debug with read-back ---");
        begin
            logic [31:0] rdata;

            // Clear CSR
            debug_mode_i          = 0;
            debug_mode_entering_i = 0;
            @(posedge clk);
            write_cpuctrl(0);

            // Enter debug mode
            debug_mode_i = 1;
            @(posedge clk);

            // SET bit 0 while in debug
            write_cpuctrl_op(32'h01, ibex_pkg::CSR_OP_SET);
            #1;
            // Output should be masked
            if (icache_enable_o !== 1'b0) begin
                $display("FAIL: T20.1: SET in debug, output should be masked");
                err_count++;
            end else begin
                $display("PASS: T20.1: SET in debug, output correctly masked");
                pass_count++;
            end

            // Read back stored value -- should show bit set
            read_cpuctrl(rdata);
            if (rdata[0] !== 1'b1) begin
                $display("FAIL: T20.2: CSR read after SET in debug should show 1");
                err_count++;
            end else begin
                $display("PASS: T20.2: CSR read after SET in debug shows 1");
                pass_count++;
            end

            // CLEAR bit 0 while in debug
            write_cpuctrl_op(32'h01, ibex_pkg::CSR_OP_CLEAR);
            read_cpuctrl(rdata);
            if (rdata[0] !== 1'b0) begin
                $display("FAIL: T20.3: CSR read after CLEAR in debug should show 0");
                err_count++;
            end else begin
                $display("PASS: T20.3: CSR read after CLEAR in debug shows 0");
                pass_count++;
            end

            // Exit debug with ic=0
            debug_mode_i = 0;
            @(posedge clk);
            #1;
            if (icache_enable_o !== 1'b0) begin
                $display("FAIL: T20.4: exited debug with ic=0, output should be 0");
                err_count++;
            end else begin
                $display("PASS: T20.4: exited debug with ic=0, output is 0");
                pass_count++;
            end
        end

        // =============================================================
        // TEST GROUP 21: debug_mode_entering without subsequent debug_mode
        //   Simulate a spurious entering pulse that is not followed by
        //   debug_mode going high (edge case / error scenario)
        // =============================================================
        $display("\n--- Test Group 21: Orphan entering pulse (no debug_mode follow-up) ---");

        debug_mode_i          = 0;
        debug_mode_entering_i = 0;
        @(posedge clk);
        write_cpuctrl(1);

        // Verify baseline
        check("T21.1: baseline ic=1",                 0, 0, 1);

        // Pulse entering for one cycle without asserting debug_mode
        debug_mode_entering_i = 1;
        @(posedge clk);
        #1;
        if (icache_enable_o !== 1'b0) begin
            $display("FAIL: T21.2: orphan entering pulse should still suppress");
            err_count++;
        end else begin
            $display("PASS: T21.2: orphan entering pulse suppresses icache");
            pass_count++;
        end

        // Deassert entering without asserting debug_mode
        debug_mode_entering_i = 0;
        @(posedge clk);
        #1;
        if (icache_enable_o !== 1'b1) begin
            $display("FAIL: T21.3: after orphan entering, icache should restore");
            err_count++;
        end else begin
            $display("PASS: T21.3: after orphan entering, icache restores");
            pass_count++;
        end

        // Multiple orphan entering pulses
        for (int i = 0; i < 5; i++) begin
            debug_mode_entering_i = 1;
            @(posedge clk);
            debug_mode_entering_i = 0;
            @(posedge clk);
        end
        #1;
        if (icache_enable_o !== 1'b1) begin
            $display("FAIL: T21.4: after multiple orphan pulses, icache should be 1");
            err_count++;
        end else begin
            $display("PASS: T21.4: icache stable after multiple orphan entering pulses");
            pass_count++;
        end

        // =============================================================
        // TEST GROUP 22: Verify icache stays disabled throughout
        //   a realistic debug session (enter, execute debug ROM code,
        //   modify CSR, exit)
        // =============================================================
        $display("\n--- Test Group 22: Realistic debug session simulation ---");
        begin
            logic [31:0] rdata;
            int session_errors = 0;

            // Pre-condition: icache enabled, normal mode
            debug_mode_i          = 0;
            debug_mode_entering_i = 0;
            @(posedge clk);
            write_cpuctrl(1);
            @(posedge clk);
            #1;
            if (icache_enable_o !== 1'b1) session_errors++;

            // Debug request arrives: entering pulse
            debug_mode_entering_i = 1;
            @(posedge clk);
            #1;
            if (icache_enable_o !== 1'b0) session_errors++;

            // Controller transitions to debug mode
            debug_mode_entering_i = 0;
            debug_mode_i          = 1;
            @(posedge clk);
            #1;
            if (icache_enable_o !== 1'b0) session_errors++;

            // Simulate several cycles of debug ROM execution
            repeat (15) begin
                @(posedge clk);
                #1;
                if (icache_enable_o !== 1'b0) session_errors++;
            end

            // Debug ROM reads CPUCTRL
            read_cpuctrl(rdata);
            if (rdata[0] !== 1'b1) session_errors++;

            // Debug ROM modifies CPUCTRL (writes 0 to disable icache for post-debug)
            write_cpuctrl(0);
            @(posedge clk);
            #1;
            if (icache_enable_o !== 1'b0) session_errors++;

            // Debug ROM sets it back
            write_cpuctrl(1);
            @(posedge clk);
            #1;
            if (icache_enable_o !== 1'b0) session_errors++;

            // Execute dret: exit debug mode
            debug_mode_i = 0;
            @(posedge clk);
            #1;
            if (icache_enable_o !== 1'b1) session_errors++;

            // Stable after exit
            repeat (5) begin
                @(posedge clk);
                #1;
                if (icache_enable_o !== 1'b1) session_errors++;
            end

            if (session_errors == 0) begin
                $display("PASS: T22: Realistic debug session - all checks passed");
                pass_count++;
            end else begin
                $display("FAIL: T22: Realistic debug session - %0d errors", session_errors);
                err_count++;
            end
        end

        // =============================================================
        // TEST GROUP 23: Alternating CSR writes between debug and normal
        //   Verify the CSR value correctly persists across mode changes
        // =============================================================
        $display("\n--- Test Group 23: Alternating writes between modes ---");
        begin
            logic [31:0] rdata;

            debug_mode_i          = 0;
            debug_mode_entering_i = 0;
            @(posedge clk);

            // Normal: write ic=1
            write_cpuctrl(1);
            check("T23.1: normal write ic=1",          0, 0, 1);

            // Debug: write ic=0
            debug_mode_i = 1;
            @(posedge clk);
            write_cpuctrl(0);
            check("T23.2: debug write ic=0",           1, 0, 0);

            // Normal: verify ic=0 persisted
            check("T23.3: exit debug, ic=0 persisted", 0, 0, 0);

            // Normal: write ic=1
            write_cpuctrl(1);
            check("T23.4: normal write ic=1 again",    0, 0, 1);

            // Debug: write ic=1 (no change)
            debug_mode_i = 1;
            @(posedge clk);
            write_cpuctrl(1);
            check("T23.5: debug write ic=1 (nop)",     1, 0, 0);

            // Normal: should still be 1
            check("T23.6: exit debug, still ic=1",     0, 0, 1);

            // Verify read-back
            read_cpuctrl(rdata);
            if (rdata[0] !== 1'b1) begin
                $display("FAIL: T23.7: read-back should show ic=1");
                err_count++;
            end else begin
                $display("PASS: T23.7: read-back confirms ic=1");
                pass_count++;
            end
        end

        // =============================================================
        // SUMMARY
        // =============================================================
        $display("\n=== Test Summary ===");
        $display("  PASSED: %0d", pass_count);
        $display("  FAILED: %0d", err_count);

        $display("Functional Coverage: %.1f%%", cg_inst.get_coverage());
        if (err_count == 0) begin
            $display("\nPASS: All ibex_cs_registers debug icache-disable tests passed!");
            $finish(0);
        end else begin
            $display("\nFAIL: %0d test(s) failed!", err_count);
            $finish(1);
        end
    end

    // ---------------------------------------------------------------
    // Waveform dump
    // ---------------------------------------------------------------
    initial begin
        $dumpfile("tb_ibex_cs_registers_icache_patch.vcd");
        $dumpvars(0);
    end

endmodule

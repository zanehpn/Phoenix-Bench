`timescale 1ns/1ps

module tb_ibex_top_pending_patch;

  // clock & reset
  logic clk;
  logic rst_n;

  // DUT I/O
  logic         test_en_i;
  logic [31:0]  hart_id_i;
  logic [31:0]  boot_addr_i;

  logic         instr_req_o;
  logic         instr_gnt_i;
  logic         instr_rvalid_i;
  logic [31:0]  instr_addr_o;
  logic [31:0]  instr_rdata_i;
  logic [6:0]   instr_rdata_intg_i;
  logic         instr_err_i;

  logic         data_req_o;
  logic         data_gnt_i;
  logic         data_rvalid_i;
  logic         data_we_o;
  logic [3:0]   data_be_o;
  logic [31:0]  data_addr_o;
  logic [31:0]  data_wdata_o;
  logic [6:0]   data_wdata_intg_o;
  logic [31:0]  data_rdata_i;
  logic [6:0]   data_rdata_intg_i;
  logic         data_err_i;

  // interrupts
  logic irq_software_i;
  logic irq_timer_i;
  logic irq_external_i;
  logic [14:0] irq_fast_i;
  logic irq_nm_i;

  // scrambling
  logic scramble_key_valid_i;
  logic [ibex_pkg::SCRAMBLE_KEY_W-1:0]   scramble_key_i;
  logic [ibex_pkg::SCRAMBLE_NONCE_W-1:0] scramble_nonce_i;
  logic scramble_req_o;

  // debug
  logic debug_req_i;
  ibex_top::crash_dump_t crash_dump_o;
  logic double_fault_seen_o;

  // external RVFI (disabled by default)
  // CPU control signals
  ibex_pkg::ibex_mubi_t fetch_enable_i;
  logic alert_minor_o;
  logic alert_major_internal_o;
  logic alert_major_bus_o;
  logic core_sleep_o;

  logic scan_rst_ni;

  // ----------------------------------------------------
  // Clock generation
  // ----------------------------------------------------
  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 100MHz
  end

  // ----------------------------------------------------
  // DUT instantiation (参数保持默认即可)
  // ----------------------------------------------------
  ibex_top #(
    .ICache(0),
    .DbgTriggerEn(0),
    .WritebackStage(0)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),

    .test_en_i(test_en_i),
    .ram_cfg_i('0),

    .hart_id_i(hart_id_i),
    .boot_addr_i(boot_addr_i),

    // instr interface
    .instr_req_o(instr_req_o),
    .instr_gnt_i(instr_gnt_i),
    .instr_rvalid_i(instr_rvalid_i),
    .instr_addr_o(instr_addr_o),
    .instr_rdata_i(instr_rdata_i),
    .instr_rdata_intg_i(instr_rdata_intg_i),
    .instr_err_i(instr_err_i),

    // data interface
    .data_req_o(data_req_o),
    .data_gnt_i(data_gnt_i),
    .data_rvalid_i(data_rvalid_i),
    .data_we_o(data_we_o),
    .data_be_o(data_be_o),
    .data_addr_o(data_addr_o),
    .data_wdata_o(data_wdata_o),
    .data_wdata_intg_o(data_wdata_intg_o),
    .data_rdata_i(data_rdata_i),
    .data_rdata_intg_i(data_rdata_intg_i),
    .data_err_i(data_err_i),

    // interrupts
    .irq_software_i(irq_software_i),
    .irq_timer_i(irq_timer_i),
    .irq_external_i(irq_external_i),
    .irq_fast_i(irq_fast_i),
    .irq_nm_i(irq_nm_i),

    // scrambling interface
    .scramble_key_valid_i(scramble_key_valid_i),
    .scramble_key_i(scramble_key_i),
    .scramble_nonce_i(scramble_nonce_i),
    .scramble_req_o(scramble_req_o),

    .debug_req_i(debug_req_i),
    .crash_dump_o(crash_dump_o),
    .double_fault_seen_o(double_fault_seen_o),

    .fetch_enable_i(fetch_enable_i),
    .alert_minor_o(alert_minor_o),
    .alert_major_internal_o(alert_major_internal_o),
    .alert_major_bus_o(alert_major_bus_o),
    .core_sleep_o(core_sleep_o),

    .scan_rst_ni(scan_rst_ni)
  );

  // ----------------------------------------------------
  // Functional Coverage
  // ----------------------------------------------------
  // Track D-side access states relevant to the PR#1917 fix:
  // The bug was that pending_dside_accesses_shifted[i-1] was accessed
  // when i==0 (out of bounds). The patch splits i==0 and i>0 cases.

  logic data_req_seen;
  logic data_gnt_seen;
  logic data_rvalid_seen;
  logic data_pending;  // req granted but not yet completed

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      data_req_seen    <= 0;
      data_gnt_seen    <= 0;
      data_rvalid_seen <= 0;
      data_pending     <= 0;
    end else begin
      data_req_seen    <= data_req_o;
      data_gnt_seen    <= data_req_o && data_gnt_i;
      data_rvalid_seen <= data_rvalid_i;
      if (data_req_o && data_gnt_i)
        data_pending <= 1;
      else if (data_rvalid_i)
        data_pending <= 0;
    end
  end

  // [verilator-strip cg] covergroup cg_dside_pending @(posedge clk);
// [verilator-strip cg]     option.per_instance = 1;

// [verilator-strip cg]     // Cover data request issued
// [verilator-strip cg]     cp_data_req: coverpoint data_req_o {
// [verilator-strip cg]       bins no_req  = {0};
// [verilator-strip cg]       bins req     = {1};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cover data grant
// [verilator-strip cg]     cp_data_gnt: coverpoint data_gnt_i {
// [verilator-strip cg]       bins no_gnt  = {0};
// [verilator-strip cg]       bins gnt     = {1};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cover data valid response
// [verilator-strip cg]     cp_data_rvalid: coverpoint data_rvalid_i {
// [verilator-strip cg]       bins no_valid = {0};
// [verilator-strip cg]       bins valid    = {1};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cover read vs write direction
// [verilator-strip cg]     cp_data_we: coverpoint data_we_o {
// [verilator-strip cg]       bins read  = {0};
// [verilator-strip cg]       bins write = {1};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cover pending transaction state
// [verilator-strip cg]     cp_pending: coverpoint data_pending {
// [verilator-strip cg]       bins idle    = {0};
// [verilator-strip cg]       bins pending = {1};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cross: request with grant (transaction handshake)
// [verilator-strip cg]     cx_req_gnt: cross cp_data_req, cp_data_gnt {
// [verilator-strip cg]       ignore_bins no_req_gnt = binsof(cp_data_req) intersect {0} && binsof(cp_data_gnt) intersect {1};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cross: request direction with grant
// [verilator-strip cg]     cx_we_gnt: cross cp_data_we, cp_data_gnt;

// [verilator-strip cg]     // Cross: pending state with new request (overlapping transactions)
// [verilator-strip cg]     cx_pending_req: cross cp_pending, cp_data_req;
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_dside_pending cg_inst = new();

  // ----------------------------------------------------
  // Stimulus – 专门触发 pending_dside_accesses
  // ----------------------------------------------------
  initial begin
    // 初始默认值
    rst_n = 0;
    test_en_i = 0;
    hart_id_i = 0;
    boot_addr_i = 32'h0000_1000;

    instr_gnt_i = 0;
    instr_rvalid_i = 0;
    instr_rdata_i = 0;
    instr_rdata_intg_i = 0;
    instr_err_i = 0;

    data_gnt_i = 0;
    data_rvalid_i = 0;
    data_rdata_i = 0;
    data_rdata_intg_i = 0;
    data_err_i = 0;

    irq_software_i = 0;
    irq_timer_i = 0;
    irq_external_i = 0;
    irq_fast_i = 0;
    irq_nm_i = 0;

    scramble_key_valid_i = 0;
    scramble_key_i = 0;
    scramble_nonce_i = 0;

    debug_req_i = 0;

    fetch_enable_i = ibex_pkg::IbexMubiOn;
    scan_rst_ni = 1;

    #20 rst_n = 1;

    // ----------------------------------------------------
    // 触发 D-side access 逻辑（你的 patch 修改部分）
    // case 1: index==0，pending_dside_accesses_shifted[0].valid==0
    // ----------------------------------------------------
    @(posedge clk);
    $display("[TB] Trigger first D-side transaction");

    force dut.data_req_o = 1;
    force dut.data_we_o  = 0;  // read
    data_gnt_i = 1;

    @(posedge clk);
    release dut.data_req_o;
    release dut.data_we_o;
    data_gnt_i = 0;

    // ----------------------------------------------------
    // 再触发 index>0 的逻辑
    // ----------------------------------------------------
    repeat(5) @(posedge clk);

    $display("[TB] Trigger next D-side entry tracking");

    force dut.data_req_o = 1;
    force dut.data_we_o  = 1;  // write
    data_gnt_i = 1;

    @(posedge clk);
    release dut.data_req_o;
    release dut.data_we_o;
    data_gnt_i = 0;

    repeat(10) @(posedge clk);

    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end


  initial begin
    $dumpfile("tb_ibex_top_pending_patch.vcd");
    $dumpvars(0);
  end

endmodule

module tb_hpdcache_evt_write_patch;

  logic core_req_valid_i;
  logic core_req_ready_o;
  logic rtab_req_valid_i;
  logic rtab_req_ready_o;
  logic refill_req_valid_i;
  logic refill_req_ready_o;

  logic st0_req_is_error_i;
  logic st0_req_is_uncacheable_i;
  logic st0_req_need_rsp_i;
  logic st0_req_is_load_i;
  logic st0_req_is_store_i;
  logic st0_req_is_amo_i;
  logic st0_req_is_cmo_fence_i;
  logic st0_req_is_cmo_inval_i;
  logic st0_req_is_cmo_prefetch_i;
  logic st0_req_mshr_check_o;
  logic st0_req_cachedir_read_o;
  logic st0_req_cachedata_read_o;

  logic st1_req_valid_i;
  logic st1_req_abort_i;
  logic st1_req_rtab_i;
  logic st1_req_is_error_i;
  logic st1_req_is_uncacheable_i;
  logic st1_req_need_rsp_i;
  logic st1_req_is_load_i;
  logic st1_req_is_store_i;
  logic st1_req_is_amo_i;
  logic st1_req_is_cmo_inval_i;
  logic st1_req_is_cmo_flush_i;
  logic st1_req_is_cmo_fence_i;
  logic st1_req_is_cmo_prefetch_i;
  logic st1_req_wr_wt_i;
  logic st1_req_wr_wb_i;
  logic st1_req_wr_auto_i;
  logic st1_dir_hit_wback_i;
  logic st1_dir_hit_dirty_i;
  logic st1_dir_hit_fetch_i;
  logic st1_dir_victim_unavailable_i;
  logic st1_dir_victim_valid_i;
  logic st1_dir_victim_wback_i;
  logic st1_dir_victim_dirty_i;
  logic st1_req_valid_o;
  logic st1_req_is_error_o;
  logic st1_rsp_valid_o;
  logic st1_rsp_error_o;
  logic st1_rsp_aborted_o;
  logic st1_req_cachedir_sel_victim_o;
  logic st1_req_cachedir_updt_sel_victim_o;
  logic st1_req_cachedata_write_o;
  logic st1_req_cachedata_write_enable_o;
  logic st1_mshr_alloc_ready_i;
  logic st1_mshr_hit_i;
  logic st1_mshr_full_i;

  logic st2_mshr_alloc_i;
  logic st2_mshr_alloc_is_prefetch_i;
  logic st2_mshr_alloc_wback_i;
  logic st2_mshr_alloc_o;
  logic st2_mshr_alloc_cs_o;
  logic st2_mshr_alloc_need_rsp_o;
  logic st2_mshr_alloc_wback_o;

  logic st2_dir_updt_i;
  logic st2_dir_updt_valid_i;
  logic st2_dir_updt_wback_i;
  logic st2_dir_updt_dirty_i;
  logic st2_dir_updt_fetch_i;
  logic st2_dir_updt_o;
  logic st2_dir_updt_valid_o;
  logic st2_dir_updt_wback_o;
  logic st2_dir_updt_dirty_o;
  logic st2_dir_updt_fetch_o;

  logic rtab_full_i;
  logic rtab_fence_i;
  logic rtab_check_o;
  logic rtab_check_hit_i;
  logic st1_rtab_alloc_o;
  logic st1_rtab_alloc_and_link_o;
  logic st1_rtab_commit_o;
  logic st1_rtab_rback_o;
  logic st1_rtab_mshr_hit_o;
  logic st1_rtab_mshr_full_o;
  logic st1_rtab_mshr_ready_o;
  logic st1_rtab_write_miss_o;
  logic st1_rtab_wbuf_hit_o;
  logic st1_rtab_wbuf_not_ready_o;
  logic st1_rtab_dir_unavailable_o;
  logic st1_rtab_dir_fetch_o;
  logic st1_rtab_flush_hit_o;
  logic st1_rtab_flush_not_ready_o;

  logic cachedir_hit_i;
  logic cachedir_init_ready_i;

  logic refill_busy_i;
  logic refill_core_rsp_valid_i;

  logic wbuf_write_ready_i;
  logic wbuf_read_hit_i;
  logic wbuf_write_valid_o;
  logic wbuf_write_uncacheable_o;
  logic wbuf_read_flush_hit_o;

  logic flush_busy_i;
  logic st1_flush_check_hit_i;
  logic st1_flush_alloc_ready_i;
  logic st2_flush_alloc_i;
  logic st2_flush_alloc_o;

  logic uc_busy_i;
  logic uc_req_valid_o;
  logic uc_core_rsp_ready_o;

  logic cmo_busy_i;
  logic cmo_wait_i;
  logic cmo_req_valid_o;

  logic cfg_prefetch_updt_plru_i;
  logic cfg_default_wb_i;

  logic evt_cache_write_miss_o;
  logic evt_cache_read_miss_o;
  logic evt_uncached_req_o;
  logic evt_cmo_req_o;
  logic evt_write_req_o;
  logic evt_read_req_o;
  logic evt_prefetch_req_o;
  logic evt_req_on_hold_o;
  logic evt_rtab_rollback_o;
  logic evt_stall_refill_o;
  logic evt_stall_o;

  hpdcache_ctrl_pe dut (.*);

  // Patch-related coverage: evt_write_req_o should fire on WB miss with error for store requests
  // [verilator-strip cg] covergroup cg_evt_write_error @(evt_write_req_o or st1_req_valid_i or st1_req_is_error_i or st1_req_is_store_i or st1_req_need_rsp_i);
// [verilator-strip cg]     option.per_instance = 1;

// [verilator-strip cg]     cp_st1_is_store: coverpoint st1_req_is_store_i {
// [verilator-strip cg]       bins store = {1};
// [verilator-strip cg]       bins no_store = {0};
// [verilator-strip cg]     }

// [verilator-strip cg]     cp_st1_is_error: coverpoint st1_req_is_error_i {
// [verilator-strip cg]       bins error = {1};
// [verilator-strip cg]       bins no_error = {0};
// [verilator-strip cg]     }

// [verilator-strip cg]     cp_st1_valid: coverpoint st1_req_valid_i {
// [verilator-strip cg]       bins valid = {1};
// [verilator-strip cg]       bins invalid = {0};
// [verilator-strip cg]     }

// [verilator-strip cg]     cp_st1_need_rsp: coverpoint st1_req_need_rsp_i {
// [verilator-strip cg]       bins need_rsp = {1};
// [verilator-strip cg]       bins no_rsp = {0};
// [verilator-strip cg]     }

// [verilator-strip cg]     cp_evt_write: coverpoint evt_write_req_o {
// [verilator-strip cg]       bins asserted = {1};
// [verilator-strip cg]       bins deasserted = {0};
// [verilator-strip cg]     }

// [verilator-strip cg]     // Cross: error store replay should set evt_write_req_o
// [verilator-strip cg]     cx_error_store_evt: cross cp_st1_is_store, cp_st1_is_error, cp_evt_write {
// [verilator-strip cg]       bins error_store_evt = binsof(cp_st1_is_store.store) && binsof(cp_st1_is_error.error) &&
// [verilator-strip cg]                              binsof(cp_evt_write.asserted);
// [verilator-strip cg]       // evt_write_req_o cannot assert for non-store
// [verilator-strip cg]       ignore_bins ig_nostore_evt = binsof(cp_st1_is_store.no_store) && binsof(cp_evt_write.asserted);
// [verilator-strip cg]       // store+error always asserts evt_write (patch behavior)
// [verilator-strip cg]       ignore_bins ig_store_err_noevt = binsof(cp_st1_is_store.store) && binsof(cp_st1_is_error.error) && binsof(cp_evt_write.deasserted);
// [verilator-strip cg]     }
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_evt_write_error cg_inst = new();

  task automatic init_inputs;
    core_req_valid_i             = 0;
    rtab_req_valid_i             = 0;
    refill_req_valid_i           = 0;

    st0_req_is_error_i           = 0;
    st0_req_is_uncacheable_i     = 0;
    st0_req_need_rsp_i           = 0;
    st0_req_is_load_i            = 0;
    st0_req_is_store_i           = 0;
    st0_req_is_amo_i             = 0;
    st0_req_is_cmo_fence_i       = 0;
    st0_req_is_cmo_inval_i       = 0;
    st0_req_is_cmo_prefetch_i    = 0;

    st1_req_valid_i              = 0;
    st1_req_abort_i              = 0;
    st1_req_rtab_i               = 0;
    st1_req_is_error_i           = 0;
    st1_req_is_uncacheable_i     = 0;
    st1_req_need_rsp_i           = 0;
    st1_req_is_load_i            = 0;
    st1_req_is_store_i           = 0;
    st1_req_is_amo_i             = 0;
    st1_req_is_cmo_inval_i       = 0;
    st1_req_is_cmo_flush_i       = 0;
    st1_req_is_cmo_fence_i       = 0;
    st1_req_is_cmo_prefetch_i    = 0;
    st1_req_wr_wt_i              = 0;
    st1_req_wr_wb_i              = 0;
    st1_req_wr_auto_i            = 0;
    st1_dir_hit_wback_i          = 0;
    st1_dir_hit_dirty_i          = 0;
    st1_dir_hit_fetch_i          = 0;
    st1_dir_victim_unavailable_i = 0;
    st1_dir_victim_valid_i       = 0;
    st1_dir_victim_wback_i       = 0;
    st1_dir_victim_dirty_i       = 0;
    st1_mshr_alloc_ready_i       = 0;
    st1_mshr_hit_i               = 0;
    st1_mshr_full_i              = 0;

    st2_mshr_alloc_i             = 0;
    st2_mshr_alloc_is_prefetch_i = 0;
    st2_mshr_alloc_wback_i       = 0;

    st2_dir_updt_i               = 0;
    st2_dir_updt_valid_i         = 0;
    st2_dir_updt_wback_i         = 0;
    st2_dir_updt_dirty_i         = 0;
    st2_dir_updt_fetch_i         = 0;

    rtab_full_i                  = 0;
    rtab_fence_i                 = 0;
    rtab_check_hit_i             = 0;

    cachedir_hit_i               = 0;
    cachedir_init_ready_i        = 1;

    refill_busy_i                = 0;
    refill_core_rsp_valid_i      = 0;

    wbuf_write_ready_i           = 0;
    wbuf_read_hit_i              = 0;

    flush_busy_i                 = 0;
    st1_flush_check_hit_i        = 0;
    st1_flush_alloc_ready_i      = 1;
    st2_flush_alloc_i            = 0;

    uc_busy_i                    = 0;
    cmo_busy_i                   = 0;
    cmo_wait_i                   = 0;

    cfg_prefetch_updt_plru_i     = 0;
    cfg_default_wb_i             = 0;
  endtask

  initial begin
    init_inputs();

    st1_req_valid_i    = 1'b1;
    st1_req_rtab_i     = 1'b1;
    st1_req_is_error_i = 1'b1;
    st1_req_need_rsp_i = 1'b1;
    st1_req_is_store_i = 1'b1;
    st1_req_wr_wb_i    = 1'b1;

    #1;
    if (evt_write_req_o === st1_req_is_store_i) begin
      $display("PASS: Write error replay flags evt_write_req_o.");
    end else begin
      $fatal(1, "FAIL: evt_write_req_o stayed low on write error replay.");
      $finish;
    end

    // ---- Additional stimulus to hit coverage bins ----

    // Test: valid=1, store=0, error=1 (load error replay)
    init_inputs();
    st1_req_valid_i    = 1'b1;
    st1_req_rtab_i     = 1'b1;
    st1_req_is_error_i = 1'b1;
    st1_req_need_rsp_i = 1'b1;
    st1_req_is_store_i = 1'b0;
    st1_req_is_load_i  = 1'b1;
    st1_req_wr_wb_i    = 1'b1;
    #1;

    // Test: valid=1, store=1, error=0 (normal store, no error)
    init_inputs();
    st1_req_valid_i    = 1'b1;
    st1_req_rtab_i     = 1'b0;
    st1_req_is_error_i = 1'b0;
    st1_req_need_rsp_i = 1'b1;
    st1_req_is_store_i = 1'b1;
    st1_req_wr_wb_i    = 1'b1;
    wbuf_write_ready_i = 1'b1;
    cachedir_hit_i     = 1'b1;
    st1_dir_hit_wback_i = 1'b1;
    #1;

    // Test: valid=0 (idle, no store, no error)
    init_inputs();
    st1_req_valid_i    = 1'b0;
    st1_req_is_error_i = 1'b0;
    st1_req_is_store_i = 1'b0;
    st1_req_need_rsp_i = 1'b0;
    #1;

    // Test: valid=1, store=0, error=0 (normal load, no error)
    init_inputs();
    st1_req_valid_i    = 1'b1;
    st1_req_is_error_i = 1'b0;
    st1_req_is_store_i = 1'b0;
    st1_req_is_load_i  = 1'b1;
    st1_req_need_rsp_i = 1'b1;
    #1;

    // Test: valid=1, store=1, error=1, need_rsp=0
    init_inputs();
    st1_req_valid_i    = 1'b1;
    st1_req_rtab_i     = 1'b1;
    st1_req_is_error_i = 1'b1;
    st1_req_need_rsp_i = 1'b0;
    st1_req_is_store_i = 1'b1;
    st1_req_wr_wb_i    = 1'b1;
    #1;

    // Test: valid=0, store=1 (invalid store)
    init_inputs();
    st1_req_valid_i    = 1'b0;
    st1_req_is_store_i = 1'b1;
    st1_req_is_error_i = 1'b1;
    #1;

    $display("Functional Coverage: %.1f%%", 0);
    $finish;
  end


  initial begin
    $dumpfile("tb_hpdcache_evt_write_patch.vcd");
    $dumpvars(0);
  end

endmodule

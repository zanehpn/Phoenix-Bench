`timescale 1ns/1ps

//  Testbench for openhwgroup_cv-hpdcache_pr33
//
//  Bug:  In hpdcache_ctrl_pe.sv on a cache-hit path for loads/prefetches,
//        the PLRU update signal was assigned as:
//            st1_req_cachedir_updt_sel_victim_o = st1_req_is_load_i;
//        This means CMO_PREFETCH (which is not a "load") never updates PLRU
//        on hit, but does update it on miss -- inconsistent behavior.
//
//  Fix:  Changed to:
//            st1_req_cachedir_updt_sel_victim_o =
//                ~st1_req_is_cmo_prefetch_i | cfg_prefetch_updt_plru_i;
//        Now for non-prefetch requests PLRU always updates on hit.
//        For prefetch, it updates only when cfg_prefetch_updt_plru_i = 1.
//
//  Strategy: Instantiate both the buggy (old) and fixed (new) DUTs.
//  The old DUT does not have cfg_prefetch_updt_plru_i, so we tie a
//  dummy wire for it (VCS will ignore unconnected ports).
//  We verify:
//    (a) Fixed DUT behaves correctly in isolation (targeted checks).
//    (b) Old vs new diverge exactly where the bug matters.

module tb_hpdcache_prefetch_plru_patch;

  // ----------------------------------------------------------------
  //  Signals
  // ----------------------------------------------------------------
  int pass_cnt = 0;
  int fail_cnt = 0;

  // Requests
  logic core_req_valid_i;
  logic rtab_req_valid_i;
  logic refill_req_valid_i;

  // Stage 0
  logic st0_req_is_error_i;
  logic st0_req_is_uncacheable_i;
  logic st0_req_need_rsp_i;
  logic st0_req_is_load_i;
  logic st0_req_is_store_i;
  logic st0_req_is_amo_i;
  logic st0_req_is_cmo_fence_i;
  logic st0_req_is_cmo_inval_i;
  logic st0_req_is_cmo_prefetch_i;

  // Stage 1
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
  logic st1_mshr_alloc_ready_i;
  logic st1_mshr_hit_i;
  logic st1_mshr_full_i;

  // Stage 2
  logic st2_mshr_alloc_i;
  logic st2_mshr_alloc_is_prefetch_i;
  logic st2_mshr_alloc_wback_i;
  logic st2_dir_updt_i;
  logic st2_dir_updt_valid_i;
  logic st2_dir_updt_wback_i;
  logic st2_dir_updt_dirty_i;
  logic st2_dir_updt_fetch_i;

  // Replay
  logic rtab_full_i;
  logic rtab_fence_i;
  logic rtab_check_hit_i;

  // Cache directory
  logic cachedir_hit_i;
  logic cachedir_init_ready_i;

  // Refill
  logic refill_busy_i;
  logic refill_core_rsp_valid_i;

  // Write buffer
  logic wbuf_write_ready_i;
  logic wbuf_read_hit_i;

  // Flush controller
  logic flush_busy_i;
  logic st1_flush_check_hit_i;
  logic st1_flush_alloc_ready_i;
  logic st2_flush_alloc_i;

  // Uncacheable handler
  logic uc_busy_i;

  // CMO
  logic cmo_busy_i;
  logic cmo_wait_i;

  // Config
  logic cfg_default_wb_i;
  logic cfg_prefetch_updt_plru_i;

  // ----------------------------------------------------------------
  //  Old (buggy) DUT outputs
  // ----------------------------------------------------------------
  logic core_req_ready_o_old;
  logic rtab_req_ready_o_old;
  logic refill_req_ready_o_old;
  logic st0_req_mshr_check_o_old;
  logic st0_req_cachedir_read_o_old;
  logic st0_req_cachedata_read_o_old;
  logic st1_req_valid_o_old;
  logic st1_req_is_error_o_old;
  logic st1_rsp_valid_o_old;
  logic st1_rsp_error_o_old;
  logic st1_rsp_aborted_o_old;
  logic st1_req_cachedir_sel_victim_o_old;
  logic st1_req_cachedir_updt_sel_victim_o_old;
  logic st1_req_cachedata_write_o_old;
  logic st1_req_cachedata_write_enable_o_old;
  logic st2_mshr_alloc_o_old;
  logic st2_mshr_alloc_cs_o_old;
  logic st2_mshr_alloc_need_rsp_o_old;
  logic st2_mshr_alloc_wback_o_old;
  logic st2_dir_updt_o_old;
  logic st2_dir_updt_valid_o_old;
  logic st2_dir_updt_wback_o_old;
  logic st2_dir_updt_dirty_o_old;
  logic st2_dir_updt_fetch_o_old;
  logic rtab_check_o_old;
  logic st1_rtab_alloc_o_old;
  logic st1_rtab_alloc_and_link_o_old;
  logic st1_rtab_commit_o_old;
  logic st1_rtab_rback_o_old;
  logic st1_rtab_mshr_hit_o_old;
  logic st1_rtab_mshr_full_o_old;
  logic st1_rtab_mshr_ready_o_old;
  logic st1_rtab_wbuf_hit_o_old;
  logic st1_rtab_wbuf_not_ready_o_old;
  logic st1_rtab_dir_unavailable_o_old;
  logic st1_rtab_dir_fetch_o_old;
  logic st1_rtab_flush_hit_o_old;
  logic st1_rtab_flush_not_ready_o_old;
  logic wbuf_write_valid_o_old;
  logic wbuf_write_uncacheable_o_old;
  logic wbuf_read_flush_hit_o_old;
  logic st2_flush_alloc_o_old;
  logic uc_req_valid_o_old;
  logic uc_core_rsp_ready_o_old;
  logic cmo_req_valid_o_old;
  logic evt_cache_write_miss_o_old;
  logic evt_cache_read_miss_o_old;
  logic evt_uncached_req_o_old;
  logic evt_cmo_req_o_old;
  logic evt_write_req_o_old;
  logic evt_read_req_o_old;
  logic evt_prefetch_req_o_old;
  logic evt_req_on_hold_o_old;
  logic evt_rtab_rollback_o_old;
  logic evt_stall_refill_o_old;
  logic evt_stall_o_old;

  // ----------------------------------------------------------------
  //  New (fixed) DUT outputs
  // ----------------------------------------------------------------
  logic core_req_ready_o_new;
  logic rtab_req_ready_o_new;
  logic refill_req_ready_o_new;
  logic st0_req_mshr_check_o_new;
  logic st0_req_cachedir_read_o_new;
  logic st0_req_cachedata_read_o_new;
  logic st1_req_valid_o_new;
  logic st1_req_is_error_o_new;
  logic st1_rsp_valid_o_new;
  logic st1_rsp_error_o_new;
  logic st1_rsp_aborted_o_new;
  logic st1_req_cachedir_sel_victim_o_new;
  logic st1_req_cachedir_updt_sel_victim_o_new;
  logic st1_req_cachedata_write_o_new;
  logic st1_req_cachedata_write_enable_o_new;
  logic st2_mshr_alloc_o_new;
  logic st2_mshr_alloc_cs_o_new;
  logic st2_mshr_alloc_need_rsp_o_new;
  logic st2_mshr_alloc_wback_o_new;
  logic st2_dir_updt_o_new;
  logic st2_dir_updt_valid_o_new;
  logic st2_dir_updt_wback_o_new;
  logic st2_dir_updt_dirty_o_new;
  logic st2_dir_updt_fetch_o_new;
  logic rtab_check_o_new;
  logic st1_rtab_alloc_o_new;
  logic st1_rtab_alloc_and_link_o_new;
  logic st1_rtab_commit_o_new;
  logic st1_rtab_rback_o_new;
  logic st1_rtab_mshr_hit_o_new;
  logic st1_rtab_mshr_full_o_new;
  logic st1_rtab_mshr_ready_o_new;
  logic st1_rtab_wbuf_hit_o_new;
  logic st1_rtab_wbuf_not_ready_o_new;
  logic st1_rtab_dir_unavailable_o_new;
  logic st1_rtab_dir_fetch_o_new;
  logic st1_rtab_flush_hit_o_new;
  logic st1_rtab_flush_not_ready_o_new;
  logic wbuf_write_valid_o_new;
  logic wbuf_write_uncacheable_o_new;
  logic wbuf_read_flush_hit_o_new;
  logic st2_flush_alloc_o_new;
  logic uc_req_valid_o_new;
  logic uc_core_rsp_ready_o_new;
  logic cmo_req_valid_o_new;
  logic evt_cache_write_miss_o_new;
  logic evt_cache_read_miss_o_new;
  logic evt_uncached_req_o_new;
  logic evt_cmo_req_o_new;
  logic evt_write_req_o_new;
  logic evt_read_req_o_new;
  logic evt_prefetch_req_o_new;
  logic evt_req_on_hold_o_new;
  logic evt_rtab_rollback_o_new;
  logic evt_stall_refill_o_new;
  logic evt_stall_o_new;

  // ================================================================
  //  Old (buggy) DUT -- note: no cfg_prefetch_updt_plru_i port
  // ================================================================
  hpdcache_ctrl_pe u_old (
    .core_req_valid_i,
    .core_req_ready_o        (core_req_ready_o_old),
    .rtab_req_valid_i,
    .rtab_req_ready_o        (rtab_req_ready_o_old),
    .refill_req_valid_i,
    .refill_req_ready_o      (refill_req_ready_o_old),
    .st0_req_is_error_i,
    .st0_req_is_uncacheable_i,
    .st0_req_need_rsp_i,
    .st0_req_is_load_i,
    .st0_req_is_store_i,
    .st0_req_is_amo_i,
    .st0_req_is_cmo_fence_i,
    .st0_req_is_cmo_inval_i,
    .st0_req_is_cmo_prefetch_i,
    .st0_req_mshr_check_o    (st0_req_mshr_check_o_old),
    .st0_req_cachedir_read_o (st0_req_cachedir_read_o_old),
    .st0_req_cachedata_read_o(st0_req_cachedata_read_o_old),
    .st1_req_valid_i,
    .st1_req_abort_i,
    .st1_req_rtab_i,
    .st1_req_is_error_i,
    .st1_req_is_uncacheable_i,
    .st1_req_need_rsp_i,
    .st1_req_is_load_i,
    .st1_req_is_store_i,
    .st1_req_is_amo_i,
    .st1_req_is_cmo_inval_i,
    .st1_req_is_cmo_flush_i,
    .st1_req_is_cmo_fence_i,
    .st1_req_is_cmo_prefetch_i,
    .st1_req_wr_wt_i,
    .st1_req_wr_wb_i,
    .st1_req_wr_auto_i,
    .st1_dir_hit_wback_i,
    .st1_dir_hit_dirty_i,
    .st1_dir_hit_fetch_i,
    .st1_dir_victim_unavailable_i,
    .st1_dir_victim_valid_i,
    .st1_dir_victim_wback_i,
    .st1_dir_victim_dirty_i,
    .st1_req_valid_o         (st1_req_valid_o_old),
    .st1_req_is_error_o      (st1_req_is_error_o_old),
    .st1_rsp_valid_o         (st1_rsp_valid_o_old),
    .st1_rsp_error_o         (st1_rsp_error_o_old),
    .st1_rsp_aborted_o       (st1_rsp_aborted_o_old),
    .st1_req_cachedir_sel_victim_o    (st1_req_cachedir_sel_victim_o_old),
    .st1_req_cachedir_updt_sel_victim_o(st1_req_cachedir_updt_sel_victim_o_old),
    .st1_req_cachedata_write_o        (st1_req_cachedata_write_o_old),
    .st1_req_cachedata_write_enable_o (st1_req_cachedata_write_enable_o_old),
    .st1_mshr_alloc_ready_i,
    .st1_mshr_hit_i,
    .st1_mshr_full_i,
    .st2_mshr_alloc_i,
    .st2_mshr_alloc_is_prefetch_i,
    .st2_mshr_alloc_wback_i,
    .st2_mshr_alloc_o        (st2_mshr_alloc_o_old),
    .st2_mshr_alloc_cs_o     (st2_mshr_alloc_cs_o_old),
    .st2_mshr_alloc_need_rsp_o(st2_mshr_alloc_need_rsp_o_old),
    .st2_mshr_alloc_wback_o  (st2_mshr_alloc_wback_o_old),
    .st2_dir_updt_i,
    .st2_dir_updt_valid_i,
    .st2_dir_updt_wback_i,
    .st2_dir_updt_dirty_i,
    .st2_dir_updt_fetch_i,
    .st2_dir_updt_o          (st2_dir_updt_o_old),
    .st2_dir_updt_valid_o    (st2_dir_updt_valid_o_old),
    .st2_dir_updt_wback_o    (st2_dir_updt_wback_o_old),
    .st2_dir_updt_dirty_o    (st2_dir_updt_dirty_o_old),
    .st2_dir_updt_fetch_o    (st2_dir_updt_fetch_o_old),
    .rtab_full_i,
    .rtab_fence_i,
    .rtab_check_o            (rtab_check_o_old),
    .rtab_check_hit_i,
    .st1_rtab_alloc_o        (st1_rtab_alloc_o_old),
    .st1_rtab_alloc_and_link_o(st1_rtab_alloc_and_link_o_old),
    .st1_rtab_commit_o       (st1_rtab_commit_o_old),
    .st1_rtab_rback_o        (st1_rtab_rback_o_old),
    .st1_rtab_mshr_hit_o     (st1_rtab_mshr_hit_o_old),
    .st1_rtab_mshr_full_o    (st1_rtab_mshr_full_o_old),
    .st1_rtab_mshr_ready_o   (st1_rtab_mshr_ready_o_old),
    .st1_rtab_wbuf_hit_o     (st1_rtab_wbuf_hit_o_old),
    .st1_rtab_wbuf_not_ready_o(st1_rtab_wbuf_not_ready_o_old),
    .st1_rtab_dir_unavailable_o(st1_rtab_dir_unavailable_o_old),
    .st1_rtab_dir_fetch_o    (st1_rtab_dir_fetch_o_old),
    .st1_rtab_flush_hit_o    (st1_rtab_flush_hit_o_old),
    .st1_rtab_flush_not_ready_o(st1_rtab_flush_not_ready_o_old),
    .cachedir_hit_i,
    .cachedir_init_ready_i,
    .refill_busy_i,
    .refill_core_rsp_valid_i,
    .wbuf_write_ready_i,
    .wbuf_read_hit_i,
    .wbuf_write_valid_o      (wbuf_write_valid_o_old),
    .wbuf_write_uncacheable_o(wbuf_write_uncacheable_o_old),
    .wbuf_read_flush_hit_o   (wbuf_read_flush_hit_o_old),
    .flush_busy_i,
    .st1_flush_check_hit_i,
    .st1_flush_alloc_ready_i,
    .st2_flush_alloc_i,
    .st2_flush_alloc_o       (st2_flush_alloc_o_old),
    .uc_busy_i,
    .uc_req_valid_o          (uc_req_valid_o_old),
    .uc_core_rsp_ready_o     (uc_core_rsp_ready_o_old),
    .cmo_busy_i,
    .cmo_wait_i,
    .cmo_req_valid_o         (cmo_req_valid_o_old),
    .cfg_prefetch_updt_plru_i,
    .cfg_default_wb_i,
    .evt_cache_write_miss_o  (evt_cache_write_miss_o_old),
    .evt_cache_read_miss_o   (evt_cache_read_miss_o_old),
    .evt_uncached_req_o      (evt_uncached_req_o_old),
    .evt_cmo_req_o           (evt_cmo_req_o_old),
    .evt_write_req_o         (evt_write_req_o_old),
    .evt_read_req_o          (evt_read_req_o_old),
    .evt_prefetch_req_o      (evt_prefetch_req_o_old),
    .evt_req_on_hold_o       (evt_req_on_hold_o_old),
    .evt_rtab_rollback_o     (evt_rtab_rollback_o_old),
    .evt_stall_refill_o      (evt_stall_refill_o_old),
    .evt_stall_o             (evt_stall_o_old)
  );

  // ================================================================
  //  New (fixed) DUT -- has cfg_prefetch_updt_plru_i port
  // ================================================================
  hpdcache_ctrl_pe_new u_new (
    .core_req_valid_i,
    .core_req_ready_o        (core_req_ready_o_new),
    .rtab_req_valid_i,
    .rtab_req_ready_o        (rtab_req_ready_o_new),
    .refill_req_valid_i,
    .refill_req_ready_o      (refill_req_ready_o_new),
    .st0_req_is_error_i,
    .st0_req_is_uncacheable_i,
    .st0_req_need_rsp_i,
    .st0_req_is_load_i,
    .st0_req_is_store_i,
    .st0_req_is_amo_i,
    .st0_req_is_cmo_fence_i,
    .st0_req_is_cmo_inval_i,
    .st0_req_is_cmo_prefetch_i,
    .st0_req_mshr_check_o    (st0_req_mshr_check_o_new),
    .st0_req_cachedir_read_o (st0_req_cachedir_read_o_new),
    .st0_req_cachedata_read_o(st0_req_cachedata_read_o_new),
    .st1_req_valid_i,
    .st1_req_abort_i,
    .st1_req_rtab_i,
    .st1_req_is_error_i,
    .st1_req_is_uncacheable_i,
    .st1_req_need_rsp_i,
    .st1_req_is_load_i,
    .st1_req_is_store_i,
    .st1_req_is_amo_i,
    .st1_req_is_cmo_inval_i,
    .st1_req_is_cmo_flush_i,
    .st1_req_is_cmo_fence_i,
    .st1_req_is_cmo_prefetch_i,
    .st1_req_wr_wt_i,
    .st1_req_wr_wb_i,
    .st1_req_wr_auto_i,
    .st1_dir_hit_wback_i,
    .st1_dir_hit_dirty_i,
    .st1_dir_hit_fetch_i,
    .st1_dir_victim_unavailable_i,
    .st1_dir_victim_valid_i,
    .st1_dir_victim_wback_i,
    .st1_dir_victim_dirty_i,
    .st1_req_valid_o         (st1_req_valid_o_new),
    .st1_req_is_error_o      (st1_req_is_error_o_new),
    .st1_rsp_valid_o         (st1_rsp_valid_o_new),
    .st1_rsp_error_o         (st1_rsp_error_o_new),
    .st1_rsp_aborted_o       (st1_rsp_aborted_o_new),
    .st1_req_cachedir_sel_victim_o    (st1_req_cachedir_sel_victim_o_new),
    .st1_req_cachedir_updt_sel_victim_o(st1_req_cachedir_updt_sel_victim_o_new),
    .st1_req_cachedata_write_o        (st1_req_cachedata_write_o_new),
    .st1_req_cachedata_write_enable_o (st1_req_cachedata_write_enable_o_new),
    .st1_mshr_alloc_ready_i,
    .st1_mshr_hit_i,
    .st1_mshr_full_i,
    .st2_mshr_alloc_i,
    .st2_mshr_alloc_is_prefetch_i,
    .st2_mshr_alloc_wback_i,
    .st2_mshr_alloc_o        (st2_mshr_alloc_o_new),
    .st2_mshr_alloc_cs_o     (st2_mshr_alloc_cs_o_new),
    .st2_mshr_alloc_need_rsp_o(st2_mshr_alloc_need_rsp_o_new),
    .st2_mshr_alloc_wback_o  (st2_mshr_alloc_wback_o_new),
    .st2_dir_updt_i,
    .st2_dir_updt_valid_i,
    .st2_dir_updt_wback_i,
    .st2_dir_updt_dirty_i,
    .st2_dir_updt_fetch_i,
    .st2_dir_updt_o          (st2_dir_updt_o_new),
    .st2_dir_updt_valid_o    (st2_dir_updt_valid_o_new),
    .st2_dir_updt_wback_o    (st2_dir_updt_wback_o_new),
    .st2_dir_updt_dirty_o    (st2_dir_updt_dirty_o_new),
    .st2_dir_updt_fetch_o    (st2_dir_updt_fetch_o_new),
    .rtab_full_i,
    .rtab_fence_i,
    .rtab_check_o            (rtab_check_o_new),
    .rtab_check_hit_i,
    .st1_rtab_alloc_o        (st1_rtab_alloc_o_new),
    .st1_rtab_alloc_and_link_o(st1_rtab_alloc_and_link_o_new),
    .st1_rtab_commit_o       (st1_rtab_commit_o_new),
    .st1_rtab_rback_o        (st1_rtab_rback_o_new),
    .st1_rtab_mshr_hit_o     (st1_rtab_mshr_hit_o_new),
    .st1_rtab_mshr_full_o    (st1_rtab_mshr_full_o_new),
    .st1_rtab_mshr_ready_o   (st1_rtab_mshr_ready_o_new),
    .st1_rtab_wbuf_hit_o     (st1_rtab_wbuf_hit_o_new),
    .st1_rtab_wbuf_not_ready_o(st1_rtab_wbuf_not_ready_o_new),
    .st1_rtab_dir_unavailable_o(st1_rtab_dir_unavailable_o_new),
    .st1_rtab_dir_fetch_o    (st1_rtab_dir_fetch_o_new),
    .st1_rtab_flush_hit_o    (st1_rtab_flush_hit_o_new),
    .st1_rtab_flush_not_ready_o(st1_rtab_flush_not_ready_o_new),
    .cachedir_hit_i,
    .cachedir_init_ready_i,
    .refill_busy_i,
    .refill_core_rsp_valid_i,
    .wbuf_write_ready_i,
    .wbuf_read_hit_i,
    .wbuf_write_valid_o      (wbuf_write_valid_o_new),
    .wbuf_write_uncacheable_o(wbuf_write_uncacheable_o_new),
    .wbuf_read_flush_hit_o   (wbuf_read_flush_hit_o_new),
    .flush_busy_i,
    .st1_flush_check_hit_i,
    .st1_flush_alloc_ready_i,
    .st2_flush_alloc_i,
    .st2_flush_alloc_o       (st2_flush_alloc_o_new),
    .uc_busy_i,
    .uc_req_valid_o          (uc_req_valid_o_new),
    .uc_core_rsp_ready_o     (uc_core_rsp_ready_o_new),
    .cmo_busy_i,
    .cmo_wait_i,
    .cmo_req_valid_o         (cmo_req_valid_o_new),
    .cfg_prefetch_updt_plru_i,
    .cfg_default_wb_i,
    .evt_cache_write_miss_o  (evt_cache_write_miss_o_new),
    .evt_cache_read_miss_o   (evt_cache_read_miss_o_new),
    .evt_uncached_req_o      (evt_uncached_req_o_new),
    .evt_cmo_req_o           (evt_cmo_req_o_new),
    .evt_write_req_o         (evt_write_req_o_new),
    .evt_read_req_o          (evt_read_req_o_new),
    .evt_prefetch_req_o      (evt_prefetch_req_o_new),
    .evt_req_on_hold_o       (evt_req_on_hold_o_new),
    .evt_rtab_rollback_o     (evt_rtab_rollback_o_new),
    .evt_stall_refill_o      (evt_stall_refill_o_new),
    .evt_stall_o             (evt_stall_o_new)
  );

  // ================================================================
  //  Helper tasks
  // ================================================================

  //  Set all inputs to a known benign default
  task init_common_inputs;
  begin
    core_req_valid_i             = 0;
    rtab_req_valid_i             = 0;
    refill_req_valid_i           = 0;

    st0_req_is_error_i           = 0;
    st0_req_is_uncacheable_i     = 0;
    st0_req_need_rsp_i           = 1;
    st0_req_is_load_i            = 0;
    st0_req_is_store_i           = 0;
    st0_req_is_amo_i             = 0;
    st0_req_is_cmo_fence_i       = 0;
    st0_req_is_cmo_inval_i       = 0;
    st0_req_is_cmo_prefetch_i    = 0;

    st1_req_valid_i              = 1;
    st1_req_abort_i              = 0;
    st1_req_rtab_i               = 0;
    st1_req_is_error_i           = 0;
    st1_req_is_uncacheable_i     = 0;
    st1_req_need_rsp_i           = 1;
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
    st1_dir_victim_valid_i       = 1;
    st1_dir_victim_wback_i       = 0;
    st1_dir_victim_dirty_i       = 0;

    st1_mshr_alloc_ready_i       = 1;
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

    cachedir_hit_i               = 1;   // default: cache hit
    cachedir_init_ready_i        = 1;

    refill_busy_i                = 0;
    refill_core_rsp_valid_i      = 0;

    wbuf_write_ready_i           = 1;
    wbuf_read_hit_i              = 0;

    flush_busy_i                 = 0;
    st1_flush_check_hit_i        = 0;
    st1_flush_alloc_ready_i      = 1;
    st2_flush_alloc_i            = 0;

    uc_busy_i                    = 0;
    cmo_busy_i                   = 0;
    cmo_wait_i                   = 0;

    cfg_default_wb_i             = 0;
    cfg_prefetch_updt_plru_i     = 0;
  end
  endtask

  // ----------------------------------------------------------------
  //  Patch-focused coverage
  // ----------------------------------------------------------------
  // [verilator-strip cg] covergroup cg_patch;
// [verilator-strip cg]     cp_is_load:       coverpoint st1_req_is_load_i;
// [verilator-strip cg]     cp_is_prefetch:   coverpoint st1_req_is_cmo_prefetch_i;
// [verilator-strip cg]     cp_cache_hit:     coverpoint cachedir_hit_i;
// [verilator-strip cg]     cp_cfg_plru:      coverpoint cfg_prefetch_updt_plru_i;
// [verilator-strip cg]     cp_valid:         coverpoint st1_req_valid_i;
// [verilator-strip cg]     cp_abort:         coverpoint st1_req_abort_i;
// [verilator-strip cg]     cp_error:         coverpoint st1_req_is_error_i;
// [verilator-strip cg]     cp_plru_updt_new: coverpoint st1_req_cachedir_updt_sel_victim_o_new;
// [verilator-strip cg]     cp_plru_updt_old: coverpoint st1_req_cachedir_updt_sel_victim_o_old;
// [verilator-strip cg]     cx_bug_scenario:  cross cp_is_prefetch, cp_cache_hit, cp_cfg_plru, cp_plru_updt_new {
// [verilator-strip cg]       // updt=1 only occurs on cache HIT paths; miss path never sets updt=1
// [verilator-strip cg]       ignore_bins miss_updt1 = binsof(cp_cache_hit) intersect {0} &&
// [verilator-strip cg]                                binsof(cp_plru_updt_new) intersect {1};
// [verilator-strip cg]       // prefetch hit cfg=0: fix gives updt = ~1|0 = 0; updt=1 unreachable
// [verilator-strip cg]       ignore_bins prefetch_hit_cfg0_updt1 = binsof(cp_is_prefetch) intersect {1} &&
// [verilator-strip cg]                                             binsof(cp_cache_hit) intersect {1} &&
// [verilator-strip cg]                                             binsof(cp_cfg_plru) intersect {0} &&
// [verilator-strip cg]                                             binsof(cp_plru_updt_new) intersect {1};
// [verilator-strip cg]     }
// [verilator-strip cg]   endgroup

  // [verilator-strip cg-inst] cg_patch cg_inst = new();

  //  Check a single signal and report
  task automatic check_signal(
    input string  label,
    input logic   actual,
    input logic   expected
  );
  begin
    /* [verilator-strip sample] */;
    if (actual !== expected) begin
      $fatal(1, "FAIL: [%s] expected=%0b actual=%0b", label, expected, actual);
      fail_cnt++;
    end else begin
      $display("  ok: [%s] = %0b", label, actual);
      pass_cnt++;
    end
  end
  endtask

  //  Compare all non-PLRU outputs between old and new DUT.
  //  They should always agree because the fix only changes the
  //  PLRU-update output on the hit path for prefetch.
  task automatic check_non_plru_outputs_match(input string label);
  begin
    #1;
    if (st1_rsp_valid_o_old   !== st1_rsp_valid_o_new   ||
        st1_rsp_error_o_old   !== st1_rsp_error_o_new   ||
        st1_rsp_aborted_o_old !== st1_rsp_aborted_o_new ||
        st1_req_cachedir_sel_victim_o_old !== st1_req_cachedir_sel_victim_o_new ||
        st1_req_cachedata_write_o_old     !== st1_req_cachedata_write_o_new     ||
        st1_req_cachedata_write_enable_o_old !== st1_req_cachedata_write_enable_o_new ||
        evt_read_req_o_old    !== evt_read_req_o_new     ||
        evt_prefetch_req_o_old!== evt_prefetch_req_o_new ||
        evt_write_req_o_old   !== evt_write_req_o_new    ||
        evt_cmo_req_o_old     !== evt_cmo_req_o_new      ||
        core_req_ready_o_old  !== core_req_ready_o_new   ||
        rtab_req_ready_o_old  !== rtab_req_ready_o_new   ||
        st1_rtab_commit_o_old !== st1_rtab_commit_o_new  ||
        st1_rtab_alloc_o_old  !== st1_rtab_alloc_o_new   ||
        st2_mshr_alloc_o_old  !== st2_mshr_alloc_o_new   ||
        st2_dir_updt_o_old    !== st2_dir_updt_o_new     ||
        st2_dir_updt_valid_o_old !== st2_dir_updt_valid_o_new) begin
      $fatal(1, "FAIL: [%s] Non-PLRU outputs diverge between old and new", label);
      fail_cnt++;
    end else begin
      $display("  ok: [%s] Non-PLRU outputs match between old and new", label);
      pass_cnt++;
    end
  end
  endtask

  // ================================================================
  //  Main test sequence
  // ================================================================
  initial begin
    $display("=========================================================");
    $display("  hpdcache_ctrl_pe PLRU prefetch patch -- testbench");
    $display("=========================================================");

    // ============================================================
    //  GROUP 1: Normal load -- cache hit
    //  PLRU should always update (both old and new)
    // ============================================================
    $display("\n--- GROUP 1: Normal load, cache hit ---");

    // 1a: load hit, cfg_prefetch_updt_plru=0
    init_common_inputs();
    st1_req_is_load_i         = 1;
    st1_req_is_cmo_prefetch_i = 0;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 0;
    #1;
    check_signal("1a new: load hit cfg=0 => PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b1);
    check_signal("1a old: load hit cfg=0 => PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b1);
    check_non_plru_outputs_match("1a");

    // 1b: load hit, cfg_prefetch_updt_plru=1
    init_common_inputs();
    st1_req_is_load_i         = 1;
    st1_req_is_cmo_prefetch_i = 0;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("1b new: load hit cfg=1 => PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b1);
    // Old DUT doesn't use cfg so still updates on load
    check_signal("1b old: load hit cfg=1 => PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b1);
    check_non_plru_outputs_match("1b");

    // ============================================================
    //  GROUP 2: Prefetch hit, cfg_prefetch_updt_plru = 0
    //  OLD: PLRU NOT updated (st1_req_is_load_i=0)
    //  NEW: PLRU NOT updated (~1 | 0 = 0)
    //  Both should agree: no PLRU update
    // ============================================================
    $display("\n--- GROUP 2: Prefetch hit, cfg=0 ---");

    // 2a: basic prefetch hit, cfg=0
    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 0;
    #1;
    check_signal("2a new: prefetch hit cfg=0 => NO PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b0);
    check_signal("2a old: prefetch hit cfg=0 => NO PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b0);
    check_non_plru_outputs_match("2a");

    // 2b: prefetch hit, cfg=0, from replay table
    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    st1_req_rtab_i            = 1;
    rtab_req_valid_i          = 1;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 0;
    #1;
    check_signal("2b new: prefetch hit cfg=0 replay => NO PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b0);
    check_signal("2b old: prefetch hit cfg=0 replay => NO PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b0);

    // 2c: prefetch hit, cfg=0, need_rsp=0
    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    st1_req_need_rsp_i        = 0;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 0;
    #1;
    check_signal("2c new: prefetch hit cfg=0 no-rsp => NO PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b0);

    // ============================================================
    //  GROUP 3: Prefetch hit, cfg_prefetch_updt_plru = 1
    //  THE BUG SCENARIO
    //  OLD: PLRU NOT updated (uses st1_req_is_load_i which is 0)
    //  NEW: PLRU IS updated  (~1 | 1 = 1)
    // ============================================================
    $display("\n--- GROUP 3: Prefetch hit, cfg=1 (THE BUG) ---");

    // 3a: basic bug scenario
    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("3a new: prefetch hit cfg=1 => PLRU UPDATED (fixed)",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b1);
    check_signal("3a old: prefetch hit cfg=1 => PLRU should be UPDATED",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b1);
    // Non-PLRU outputs should still match
    check_non_plru_outputs_match("3a");

    // 3b: bug scenario with replay
    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    st1_req_rtab_i            = 1;
    rtab_req_valid_i          = 1;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("3b new: prefetch hit cfg=1 replay => PLRU UPDATED",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b1);
    check_signal("3b old: prefetch hit cfg=1 replay => PLRU should be UPDATED",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b1);

    // 3c: bug scenario with need_rsp=0
    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    st1_req_need_rsp_i        = 0;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("3c new: prefetch hit cfg=1 no-rsp => PLRU UPDATED",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b1);

    // 3d: bug scenario with wt write hint
    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    st1_req_wr_wt_i           = 1;
    st1_dir_hit_wback_i       = 1;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("3d new: prefetch hit cfg=1 wt hint => PLRU UPDATED",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b1);
    check_signal("3d old: prefetch hit cfg=1 wt hint => PLRU should be UPDATED",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b1);

    // ============================================================
    //  GROUP 4: Cache miss path
    //  On miss, PLRU is updated via a different code path (line 873/937)
    //  Both old and new should behave the same on miss.
    // ============================================================
    $display("\n--- GROUP 4: Cache miss ---");

    // 4a: load miss
    init_common_inputs();
    st1_req_is_load_i         = 1;
    st1_req_is_cmo_prefetch_i = 0;
    cachedir_hit_i            = 0;  // MISS
    cfg_prefetch_updt_plru_i  = 0;
    #1;
    check_signal("4a new: load miss => updt_sel_victim for miss alloc",
                 st1_req_cachedir_updt_sel_victim_o_new,
                 st1_req_cachedir_updt_sel_victim_o_old);
    check_non_plru_outputs_match("4a");

    // 4b: prefetch miss, cfg=0
    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    cachedir_hit_i            = 0;  // MISS
    cfg_prefetch_updt_plru_i  = 0;
    #1;
    check_signal("4b: prefetch miss cfg=0 => old==new",
                 st1_req_cachedir_updt_sel_victim_o_new,
                 st1_req_cachedir_updt_sel_victim_o_old);

    // 4c: prefetch miss, cfg=1
    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    cachedir_hit_i            = 0;  // MISS
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("4c: prefetch miss cfg=1 => old==new",
                 st1_req_cachedir_updt_sel_victim_o_new,
                 st1_req_cachedir_updt_sel_victim_o_old);

    // 4d: load miss, cfg=1
    init_common_inputs();
    st1_req_is_load_i         = 1;
    st1_req_is_cmo_prefetch_i = 0;
    cachedir_hit_i            = 0;  // MISS
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("4d new: load miss cfg=1 => old==new",
                 st1_req_cachedir_updt_sel_victim_o_new,
                 st1_req_cachedir_updt_sel_victim_o_old);
    check_non_plru_outputs_match("4d");

    // ============================================================
    //  GROUP 5: Performance event consistency
    //  evt_read_req and evt_prefetch_req should be mutually exclusive
    // ============================================================
    $display("\n--- GROUP 5: Performance events ---");

    // 5a: load hit => evt_read_req=1, evt_prefetch_req=0
    init_common_inputs();
    st1_req_is_load_i         = 1;
    st1_req_is_cmo_prefetch_i = 0;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 0;
    #1;
    check_signal("5a new: load => evt_read_req=1",
                 evt_read_req_o_new, 1'b1);
    check_signal("5a new: load => evt_prefetch_req=0",
                 evt_prefetch_req_o_new, 1'b0);

    // 5b: prefetch hit => evt_read_req=0, evt_prefetch_req=1
    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("5b new: prefetch => evt_read_req=0",
                 evt_read_req_o_new, 1'b0);
    check_signal("5b new: prefetch => evt_prefetch_req=1",
                 evt_prefetch_req_o_new, 1'b1);
    // These events should match between old and new (fix doesn't affect them)
    check_signal("5b: evt_read_req old==new",
                 evt_read_req_o_old, evt_read_req_o_new);
    check_signal("5b: evt_prefetch_req old==new",
                 evt_prefetch_req_o_old, evt_prefetch_req_o_new);

    // ============================================================
    //  GROUP 6: Abort / error / invalid-request edge cases
    //  When st1_req_valid_i=0 or abort=1, PLRU should NOT update
    // ============================================================
    $display("\n--- GROUP 6: Abort and invalid request ---");

    // 6a: prefetch hit, cfg=1, but request is invalid (st1_req_valid_i=0)
    init_common_inputs();
    st1_req_valid_i           = 0;   // no valid request in stage 1
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("6a new: invalid req => NO PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b0);
    check_signal("6a old: invalid req => NO PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b0);

    // 6b: prefetch hit, cfg=1, but request is aborted
    init_common_inputs();
    st1_req_valid_i           = 1;
    st1_req_abort_i           = 1;
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("6b new: aborted req => NO PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b0);
    check_signal("6b old: aborted req => NO PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b0);

    // 6c: prefetch hit, cfg=1, but request is error
    init_common_inputs();
    st1_req_valid_i           = 1;
    st1_req_is_error_i        = 1;
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("6c new: error req => NO PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b0);
    check_signal("6c old: error req => NO PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b0);

    // ============================================================
    //  GROUP 7: Store request -- should not be affected by fix
    // ============================================================
    $display("\n--- GROUP 7: Store request ---");

    // 7a: store hit
    init_common_inputs();
    st1_req_is_store_i        = 1;
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 0;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 0;
    #1;
    check_signal("7a: store hit => old==new PLRU",
                 st1_req_cachedir_updt_sel_victim_o_new,
                 st1_req_cachedir_updt_sel_victim_o_old);
    check_non_plru_outputs_match("7a");

    // 7b: store miss
    init_common_inputs();
    st1_req_is_store_i        = 1;
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 0;
    cachedir_hit_i            = 0;
    cfg_prefetch_updt_plru_i  = 0;
    #1;
    check_signal("7b: store miss => old==new PLRU",
                 st1_req_cachedir_updt_sel_victim_o_new,
                 st1_req_cachedir_updt_sel_victim_o_old);

    // 7c: error request hit, cfg=0 -- covers cross bin (prefetch=0, hit=1, cfg=0, updt=0)
    init_common_inputs();
    st1_req_is_error_i        = 1;
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 0;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 0;
    #1;
    check_signal("7c new: error req hit cfg=0 => NO PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b0);
    check_signal("7c old: error req hit cfg=0 => NO PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b0);

    // ============================================================
    //  GROUP 8: CMO inval / flush -- should not be affected by fix
    // ============================================================
    $display("\n--- GROUP 8: CMO inval/flush ---");

    // 8a: CMO inval
    init_common_inputs();
    st1_req_is_cmo_inval_i    = 1;
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 0;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("8a: CMO inval => old==new PLRU",
                 st1_req_cachedir_updt_sel_victim_o_new,
                 st1_req_cachedir_updt_sel_victim_o_old);

    // 8b: CMO flush
    init_common_inputs();
    st1_req_is_cmo_flush_i    = 1;
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 0;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    st1_flush_alloc_ready_i   = 1;
    st1_flush_check_hit_i     = 0;
    #1;
    check_signal("8b: CMO flush => old==new PLRU",
                 st1_req_cachedir_updt_sel_victim_o_new,
                 st1_req_cachedir_updt_sel_victim_o_old);

    // ============================================================
    //  GROUP 9: Uncacheable request -- should not be affected
    // ============================================================
    $display("\n--- GROUP 9: Uncacheable request ---");

    init_common_inputs();
    st1_req_is_uncacheable_i  = 1;
    st1_req_is_load_i         = 1;
    st1_req_is_cmo_prefetch_i = 0;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("9a: uncacheable => old==new PLRU",
                 st1_req_cachedir_updt_sel_victim_o_new,
                 st1_req_cachedir_updt_sel_victim_o_old);
    check_non_plru_outputs_match("9a");

    // ============================================================
    //  GROUP 10: Prefetch hit with dir_hit_fetch_i=1
    //  When the cacheline is being fetched, state update is blocked.
    //  The PLRU update signal should still be set (it gates differently),
    //  but let's verify consistency.
    // ============================================================
    $display("\n--- GROUP 10: Prefetch hit with fetch in progress ---");

    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    cachedir_hit_i            = 1;
    st1_dir_hit_fetch_i       = 1;  // currently being fetched
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("10a new: prefetch hit+fetch cfg=1 => PLRU UPDATED",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b1);
    check_signal("10a old: prefetch hit+fetch cfg=1 => PLRU should be UPDATED",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b1);

    // ============================================================
    //  GROUP 11: Replay-table interactions
    // ============================================================
    $display("\n--- GROUP 11: Replay table ---");

    // 11a: prefetch hit from replay, no new rtab request available
    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    st1_req_rtab_i            = 1;
    rtab_req_valid_i          = 0;  // no next replay request
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("11a new: prefetch replay no-next cfg=1 => PLRU UPDATED",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b1);
    check_signal("11a old: prefetch replay no-next cfg=1 => PLRU should be UPDATED",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b1);

    // 11b: prefetch hit from replay, next replay available
    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    st1_req_rtab_i            = 1;
    rtab_req_valid_i          = 1;  // next replay available
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("11b new: prefetch replay with-next cfg=1 => PLRU UPDATED",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b1);

    // ============================================================
    //  GROUP 12: MSHR hit / full edge cases (cachedir_hit=1 path)
    //  When MSHR hits or is full on the hit path, the request
    //  should be stalled/allocated to replay table, not processed.
    // ============================================================
    $display("\n--- GROUP 12: MSHR hit/full on cache-hit path ---");

    // 12a: prefetch hit but MSHR hit (someone else fetching same line)
    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    cachedir_hit_i            = 1;
    st1_mshr_hit_i            = 1;  // MSHR collision
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    // On MSHR hit with cachedir_hit, the load/prefetch still processes
    // since the data is in the cache. PLRU should still update.
    check_signal("12a: prefetch hit + mshr_hit => old==new for non-PLRU",
                 st1_rsp_valid_o_new, st1_rsp_valid_o_old);

    // ============================================================
    //  GROUP 13: Wbuf read hit on cache-hit path
    //  Write buffer read hit can cause stall/replay on cache hit.
    // ============================================================
    $display("\n--- GROUP 13: Write buffer read hit ---");

    // 13a: prefetch hit, wbuf_read_hit=1
    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    cachedir_hit_i            = 1;
    wbuf_read_hit_i           = 1;  // write buffer has newer data
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    // wbuf_read_hit should cause the request to be replayed, not committed
    check_signal("13a: wbuf_read_hit => check rtab alloc consistency",
                 st1_rtab_alloc_o_new, st1_rtab_alloc_o_old);

    // ============================================================
    //  GROUP 14: cfg_prefetch_updt_plru toggling mid-scenario
    //  Verify the signal responds immediately (combinational)
    // ============================================================
    $display("\n--- GROUP 14: Dynamic cfg toggle ---");

    init_common_inputs();
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 0;
    #1;
    check_signal("14a new: prefetch hit cfg=0 => NO PLRU",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b0);
    // Now toggle cfg to 1
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("14b new: toggle cfg to 1 => PLRU UPDATED",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b1);
    // Toggle back
    cfg_prefetch_updt_plru_i  = 0;
    #1;
    check_signal("14c new: toggle cfg back to 0 => NO PLRU",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b0);

    // ============================================================
    //  GROUP 15: Refill path -- request comes from refill port
    // ============================================================
    $display("\n--- GROUP 15: Refill request ---");

    init_common_inputs();
    refill_req_valid_i        = 1;
    core_req_valid_i          = 0;
    rtab_req_valid_i          = 0;
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 0;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    // When none of load/store/amo/cmo are asserted, the PE defaults
    check_signal("15a: refill req => old==new PLRU",
                 st1_req_cachedir_updt_sel_victim_o_new,
                 st1_req_cachedir_updt_sel_victim_o_old);

    // ============================================================
    //  GROUP 16: AMO request -- should not be affected
    // ============================================================
    $display("\n--- GROUP 16: AMO request ---");

    init_common_inputs();
    st1_req_is_amo_i          = 1;
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 0;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("16a: AMO => old==new PLRU",
                 st1_req_cachedir_updt_sel_victim_o_new,
                 st1_req_cachedir_updt_sel_victim_o_old);
    check_non_plru_outputs_match("16a");

    // ============================================================
    //  GROUP 17: CMO fence -- should not be affected
    // ============================================================
    $display("\n--- GROUP 17: CMO fence ---");

    init_common_inputs();
    st1_req_is_cmo_fence_i    = 1;
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 0;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("17a: CMO fence => old==new PLRU",
                 st1_req_cachedir_updt_sel_victim_o_new,
                 st1_req_cachedir_updt_sel_victim_o_old);

    // ============================================================
    //  GROUP 18: Load hit from replay table
    //  Should always update PLRU regardless of cfg
    // ============================================================
    $display("\n--- GROUP 18: Load hit from replay ---");

    init_common_inputs();
    st1_req_is_load_i         = 1;
    st1_req_is_cmo_prefetch_i = 0;
    st1_req_rtab_i            = 1;
    rtab_req_valid_i          = 0;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 0;
    #1;
    check_signal("18a new: load replay hit cfg=0 => PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b1);
    check_signal("18a old: load replay hit cfg=0 => PLRU update",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b1);

    // ============================================================
    //  GROUP 19: Simultaneous load+prefetch flags (illegal but safe)
    //  Test that the fixed logic still produces a value.
    // ============================================================
    $display("\n--- GROUP 19: Both load and prefetch asserted ---");

    init_common_inputs();
    st1_req_is_load_i         = 1;
    st1_req_is_cmo_prefetch_i = 1;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 0;
    #1;
    // New: ~1 | 0 = 0. Old: load_i=1. They diverge.
    // With both load and prefetch set (corner case), new logic says no PLRU update when cfg=0.
    check_signal("19a new: load+prefetch cfg=0 => PLRU=0 (~1|0)",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b0);
    check_signal("19a old: load+prefetch cfg=0 => should match new",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b0);

    init_common_inputs();
    st1_req_is_load_i         = 1;
    st1_req_is_cmo_prefetch_i = 1;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    // New: ~1 | 1 = 1. Old: load_i=1. Both agree.
    check_signal("19b new: load+prefetch cfg=1 => PLRU=1",
                 st1_req_cachedir_updt_sel_victim_o_new, 1'b1);
    check_signal("19b old: load+prefetch cfg=1 => PLRU=1",
                 st1_req_cachedir_updt_sel_victim_o_old, 1'b1);

    // ============================================================
    //  GROUP 20: Cache init not ready
    // ============================================================
    $display("\n--- GROUP 20: Cache init not ready ---");

    init_common_inputs();
    cachedir_init_ready_i     = 0;
    st1_req_is_load_i         = 0;
    st1_req_is_cmo_prefetch_i = 1;
    cachedir_hit_i            = 1;
    cfg_prefetch_updt_plru_i  = 1;
    #1;
    check_signal("20a: cachedir not ready => old==new PLRU",
                 st1_req_cachedir_updt_sel_victim_o_new,
                 st1_req_cachedir_updt_sel_victim_o_old);

    // ============================================================
    //  Summary
    // ============================================================
    $display("\n=========================================================");
    $display("  RESULTS: %0d passed, %0d failed", pass_cnt, fail_cnt);
    $display("=========================================================");

    if (fail_cnt == 0) begin
      $display("PASS: All checks passed.");
    end else begin
      $fatal(1, "FAIL: %0d check(s) failed.", fail_cnt);
    end

    $display("Functional Coverage: %.1f%%", 0);
    if (fail_cnt > 0)
      $finish;
    else
      $finish;
  end

  // ----------------------------------------------------------------
  //  VCD dump
  // ----------------------------------------------------------------
  initial begin
    $dumpfile("tb_hpdcache_prefetch_plru_patch.vcd");
    $dumpvars(0);
  end

endmodule

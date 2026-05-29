#!/bin/bash

SNAP=../../snapshots/lowRISC_ibex_pr1865
PRIM_RTL=$SNAP/vendor/lowrisc_ip/ip/prim/rtl
PRIM_GENERIC=$SNAP/vendor/lowrisc_ip/ip/prim_generic/rtl
PRIM_DV=$SNAP/dv/uvm/core_ibex/common/prim
DV_UTILS=$SNAP/vendor/lowrisc_ip/dv/sv/dv_utils

vcs -cm line+cond+tgl+branch+fsm -sverilog \
    +incdir+$PRIM_RTL \
    +incdir+$SNAP/rtl \
    +incdir+$DV_UTILS \
    -CFLAGS "-DVCS" \
    +define+SYNTHESIS= \
    +define+DV_FCOV_DISABLE \
    $PRIM_RTL/prim_assert.sv \
    $DV_UTILS/dv_fcov_macros.svh \
    $PRIM_DV/prim_pkg.sv \
    $SNAP/rtl/ibex_pkg.sv \
    $PRIM_GENERIC/prim_generic_buf.sv \
    $PRIM_GENERIC/prim_generic_flop.sv \
    $PRIM_GENERIC/prim_generic_clock_gating.sv \
    $PRIM_GENERIC/prim_generic_clock_mux2.sv \
    $PRIM_DV/prim_buf.sv \
    $PRIM_DV/prim_flop.sv \
    $PRIM_DV/prim_clock_gating.sv \
    $PRIM_DV/prim_clock_mux2.sv \
    $SNAP/rtl/ibex_alu.sv \
    $SNAP/rtl/ibex_branch_predict.sv \
    $SNAP/rtl/ibex_compressed_decoder.sv \
    $SNAP/rtl/ibex_controller.sv \
    $SNAP/rtl/ibex_counter.sv \
    $SNAP/rtl/ibex_cs_registers.sv \
    $SNAP/rtl/ibex_csr.sv \
    $SNAP/rtl/ibex_decoder.sv \
    $SNAP/rtl/ibex_dummy_instr.sv \
    $SNAP/rtl/ibex_ex_block.sv \
    $SNAP/rtl/ibex_fetch_fifo.sv \
    $SNAP/rtl/ibex_icache.sv \
    $SNAP/rtl/ibex_id_stage.sv \
    $SNAP/rtl/ibex_if_stage.sv \
    $SNAP/rtl/ibex_load_store_unit.sv \
    $SNAP/rtl/ibex_multdiv_fast.sv \
    $SNAP/rtl/ibex_multdiv_slow.sv \
    $SNAP/rtl/ibex_pmp.sv \
    $SNAP/rtl/ibex_prefetch_buffer.sv \
    $SNAP/rtl/ibex_register_file_ff.sv \
    $SNAP/rtl/ibex_wb_stage.sv \
    $SNAP/rtl/ibex_core.sv \
    tb_if_stage_patch.sv \
    -top tb_if_stage_patch -full64 -debug_access+all \
    -timescale=1ns/1ps \
    +nospecify \
    -suppress=PCWM-L \
    2>&1 | tail -20

echo "--- Running simulation ---"
./simv -cm line+cond+tgl+branch+fsm +vcs+flush+all 2>&1 | tee simv.log | tail -60

# Check results
if grep -q "SOME TESTS FAILED" simv.log; then
    echo "FAIL"
elif grep -q "^FAIL:" simv.log; then
    echo "FAIL"
elif grep -q "ALL TESTS PASSED" simv.log; then
    echo "PASS"
else
    echo "FAIL: No clear verdict found"
fi

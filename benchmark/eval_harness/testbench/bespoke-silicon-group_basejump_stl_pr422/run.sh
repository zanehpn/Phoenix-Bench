vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
    -assert svaext \
    +incdir+../../snapshots/bespoke-silicon-group_basejump_stl_pr422/bsg_misc \
    ../../snapshots/bespoke-silicon-group_basejump_stl_pr422/bsg_misc/bsg_defines.v \
    ../../snapshots/bespoke-silicon-group_basejump_stl_pr422/bsg_test/bsg_nonsynth_clock_gen.v \
    ../../snapshots/bespoke-silicon-group_basejump_stl_pr422/bsg_test/bsg_nonsynth_dpi_clock_gen.v \
    ../../snapshots/bespoke-silicon-group_basejump_stl_pr422/bsg_misc/bsg_circular_ptr.v \
    ../../snapshots/bespoke-silicon-group_basejump_stl_pr422/bsg_dataflow/bsg_fifo_tracker.v \
    ../../snapshots/bespoke-silicon-group_basejump_stl_pr422/bsg_test/bsg_nonsynth_reset_gen.v \
    ../../snapshots/bespoke-silicon-group_basejump_stl_pr422/bsg_test/bsg_nonsynth_dpi_from_fifo.v \
    ../../snapshots/bespoke-silicon-group_basejump_stl_pr422/bsg_test/bsg_nonsynth_dpi_to_fifo.v \
    ../../snapshots/bespoke-silicon-group_basejump_stl_pr422/bsg_mem/bsg_mem_1r1w_synth.v \
    ../../snapshots/bespoke-silicon-group_basejump_stl_pr422/bsg_mem/bsg_mem_1r1w.v \
    ../../snapshots/bespoke-silicon-group_basejump_stl_pr422/bsg_dataflow/bsg_fifo_1r1w_small_unhardened.v \
    ../../snapshots/bespoke-silicon-group_basejump_stl_pr422/testing/bsg_test/bsg_nonsynth_dpi/top.v  2>&1 | tee simv.log

COMPILE_FAIL=0
if grep -q "Error" simv.log ; then
  echo "FAIL: Multiple errors found."
  COMPILE_FAIL=1
fi

vcs -full64 -sverilog \
    tb_dpi_clock_gen_patch.sv \
    -top tb_dpi_clock_gen_patch \
    -o simv_cov 2>&1 | tee compile_cov.log

./simv_cov 2>&1 | tee simv_cov.log

if [ "$COMPILE_FAIL" -eq 0 ] && grep -q "PASS:" simv_cov.log; then
  echo "PASS: No errors found."
else
  echo "FAIL: Multiple errors found."
fi

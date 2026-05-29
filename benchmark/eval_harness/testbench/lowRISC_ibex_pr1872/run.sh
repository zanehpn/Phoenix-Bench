vcs -cm line+cond+tgl+branch+fsm -sverilog +define+SYNTHESIS \
  +incdir+../../snapshots/lowRISC_ibex_pr1872/vendor/lowrisc_ip/ip/prim/rtl \
  +incdir+../../snapshots/lowRISC_ibex_pr1872/rtl \
  +incdir+../../snapshots/lowRISC_ibex_pr1872/vendor/lowrisc_ip/dv/sv/dv_utils \
  ../../snapshots/lowRISC_ibex_pr1872/vendor/lowrisc_ip/ip/prim/rtl/prim_assert.sv \
  ../../snapshots/lowRISC_ibex_pr1872/rtl/ibex_pkg.sv \
  ../../snapshots/lowRISC_ibex_pr1872/rtl/ibex_fetch_fifo.sv \
  ../../snapshots/lowRISC_ibex_pr1872/rtl/ibex_icache.sv \
  ../../snapshots/lowRISC_ibex_pr1872/rtl/ibex_prefetch_buffer.sv \
  ../../snapshots/lowRISC_ibex_pr1872/rtl/ibex_dummy_instr.sv \
  ../../snapshots/lowRISC_ibex_pr1872/rtl/ibex_compressed_decoder.sv \
  ../../snapshots/lowRISC_ibex_pr1872/rtl/ibex_core.sv \
  ../../snapshots/lowRISC_ibex_pr1872/rtl/ibex_id_stage.sv \
  ../../snapshots/lowRISC_ibex_pr1872/rtl/ibex_controller.sv \
  tb_ibex_controller_ebreak_patch.sv \
  -top tb_ibex_controller_ebreak_patch \
  -full64 -debug_access+all


./simv -cm line+cond+tgl+branch+fsm 2>&1 | tee simv.log

# Check results
if grep -q "^FAIL " simv.log || grep -q "SOME TESTS FAILED" simv.log || grep -q "Illegal bin hit" simv.log; then
    echo "FAIL"
elif grep -q "ALL TESTS PASSED" simv.log; then
    echo "PASS"
else
    echo "FAIL: No clear verdict found"
fi

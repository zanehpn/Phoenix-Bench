SNAP=../../snapshots/bespoke-silicon-group_basejump_stl_pr675

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
    -assert svaext \
    +incdir+${SNAP}/bsg_misc \
    ${SNAP}/bsg_misc/bsg_defines.sv \
    ${SNAP}/bsg_misc/bsg_dff.sv  \
    ${SNAP}/bsg_misc/bsg_dff_en_bypass.sv \
    ${SNAP}/bsg_misc/bsg_dff_en.sv \
    ${SNAP}/bsg_mem/bsg_mem_1r1w.sv \
    ${SNAP}/bsg_mem/bsg_mem_1rw_sync_mask_write_bit_from_1r1w.sv 2>&1 | tee simv.log

COMPILE_FAIL=0
if grep -q "Error" simv.log ; then
  echo "FAIL: Lint errors found."
  COMPILE_FAIL=1
fi

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
    +incdir+${SNAP}/bsg_misc \
    ${SNAP}/bsg_misc/bsg_defines.sv \
    ${SNAP}/bsg_misc/bsg_dff.sv \
    ${SNAP}/bsg_misc/bsg_dff_en_bypass.sv \
    ${SNAP}/bsg_misc/bsg_dff_en.sv \
    ${SNAP}/bsg_mem/bsg_mem_1r1w_sync.sv \
    ${SNAP}/bsg_mem/bsg_mem_1r1w_sync_synth.sv \
    ${SNAP}/bsg_mem/bsg_mem_1r1w.sv \
    ${SNAP}/bsg_mem/bsg_mem_1rw_sync_mask_write_bit_from_1r1w.sv \
    tb_mem_1rw_decl_order_patch.sv \
    -top tb_mem_1rw_decl_order_patch \
    -o simv_cov 2>&1 | tee compile_cov.log

./simv_cov -cm line+cond+tgl+branch+fsm 2>&1 | tee simv_cov.log

if [ "$COMPILE_FAIL" -eq 0 ] && grep -q "PASS:" simv_cov.log; then
  echo "PASS: No errors found."
else
  echo "FAIL: Lint errors found."
fi

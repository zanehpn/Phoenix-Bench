#!/bin/bash


SNAP=../../snapshots/openhwgroup_cv32e40s_pr263

vcs -cm line+cond+tgl+branch+fsm -sverilog \
  "$SNAP/rtl/include/cv32e40s_pkg.sv" \
  "$SNAP/bhv/include/cv32e40s_rvfi_pkg.sv" \
  "$SNAP/rtl/if_c_obi.sv" \
  "$SNAP/bhv/cv32e40s_rvfi_instr_obi.sv" \
  "$SNAP/bhv/cv32e40s_rvfi_data_obi.sv" \
  "$SNAP/bhv/cv32e40s_rvfi.sv" \
  tb_cv32e40s_rvfi_mode_patch.sv \
  -top tb_cv32e40s_rvfi_mode_patch \
  -full64 -debug_access+all

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS:" simv.log; then
  echo "PASS: rvfi_mode reset behavior matches the fix."
else
  echo "FAIL: rvfi_mode reset behavior did not match expectations."
fi

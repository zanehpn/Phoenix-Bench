#!/bin/bash

SNAP=../../snapshots/openhwgroup_cvfpu_pr114
CCELL=../../../common_cells/

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  +define+TARGET_VSIM \
  -assert svaext \
  +incdir+"$CCELL/include" \
  -f ../../../common_cells/filelist.f \
  "$SNAP/src/fpnew_pkg.sv" \
  "$SNAP/src/fpnew_rounding.sv" \
  "$SNAP/src/fpnew_classifier.sv" \
  fpnew_fma_multi_patched.sv \
  tb_fpnew_adds_widen_patch.sv \
  -top tb_fpnew_adds_widen_patch \
  -full64 -debug_access+all \
  -o simv 2>&1 | tee compile.log

if [ $? -ne 0 ]; then
  echo "FAIL: Compilation failed."
fi

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS: All tests passed." simv.log; then
  echo "PASS"
elif grep -q "FAIL" simv.log; then
  echo "FAIL"
else
  echo "FAIL: No clear verdict found"
fi

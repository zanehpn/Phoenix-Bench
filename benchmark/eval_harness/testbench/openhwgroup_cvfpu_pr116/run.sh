#!/bin/bash

SNAP=../../snapshots/openhwgroup_cvfpu_pr116
CCELL=../../../common_cells/include

vcs -cm line+cond+tgl+branch+fsm -sverilog \
  +incdir+"$CCELL" \
  "$SNAP/src/fpnew_pkg.sv" \
  "$SNAP/src/fpnew_rounding.sv" \
  "$SNAP/src/fpnew_classifier.sv" \
  "$SNAP/src/fpnew_noncomp.sv" \
  tb_fpnew_noncomp_snan_patch.sv \
  -top tb_fpnew_noncomp_snan_patch \
  -full64 -debug_access+all

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

# Check for overall pass/fail from the testbench summary
if grep -q "^PASS: All" simv.log; then
  echo "RESULT: PASS -- all comparison tests passed including sNaN NEQ fix."
elif grep -q "^FAIL:" simv.log; then
  echo "RESULT: FAIL -- some comparison tests failed. See simv.log for details."
elif grep -q "Error-\|FAIL\|Illegal bin" simv.log; then
  echo "FAIL: simulation detected bug (illegal bin hit or error). See simv.log for details."
else
  echo "FAIL: simulation did not produce expected output."
fi

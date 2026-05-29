#!/bin/bash

SNAP=../../snapshots/openhwgroup_cvw_pr1555

vcs -sverilog -full64 -cm line+cond+tgl+branch+fsm -debug_access+all \
  -timescale=1ns/1ps \
  "$SNAP/testbench/common/ramxdetector.sv" \
  tb_ramxdetector_stall_patch.sv \
  -top tb_ramxdetector_stall_patch \
  -o simv 2>&1 | tee compile.log

if [ ! -x simv ]; then
  echo "FAIL: Compilation failed (StallW port likely missing in unpatched code)."
elif ! ./simv -cm line+cond+tgl+branch+fsm 2>&1 | tee simv.log; then
  echo "FAIL: Simulation error."
elif grep -q "^FAIL:" simv.log; then
  echo "FAIL: One or more tests failed. See simv.log for details."
elif grep -q "^PASS:" simv.log; then
  echo "PASS: All tests passed."
else
  echo "FAIL: No clear verdict found."
fi

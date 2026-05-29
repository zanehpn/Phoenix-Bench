#!/bin/bash

SNAP="../../snapshots/pulp-platform_common_cells_pr182"

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  -assert svaext \
   +incdir+"$SNAP/include" \
  ../../../tech_cells_generic/src/rtl/tc_clk.sv \
  "$SNAP/src/clk_int_div.sv" \
  tb_common_cells_clk_int_div_patch.sv \
  -top tb_common_cells_clk_int_div_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

# Check results
if grep -q "WATCHDOG" simv.log; then
  echo "FAIL: Simulation timed out (likely FSM deadlock)."
elif grep -q "FAIL:" simv.log; then
  echo "FAIL: clk_int_div testbench detected errors."
elif grep -q "PASS: All tests passed" simv.log; then
  echo "PASS: clk_int_div testbench passed all tests."
else
  echo "INCONCLUSIVE: Could not determine test result. Check simv.log."
fi

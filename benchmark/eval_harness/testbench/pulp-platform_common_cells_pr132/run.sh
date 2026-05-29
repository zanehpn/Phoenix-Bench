#!/bin/bash
SNAP=../../snapshots/pulp-platform_common_cells_pr132
TC_CLK=../../snapshots/pulp-platform_tech_cells_generic_pr30/src/rtl/tc_clk.sv

# The patch adds src/clk_int_div.sv as a NEW module.
if [ ! -f "$SNAP/src/clk_int_div.sv" ]; then
  echo "FAIL: clk_int_div.sv module not found in snapshot (patch not applied)."
else
  rm -rf simv simv.daidir csrc

  vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
    -timescale=1ns/1ps \
    -assert svaext \
    +incdir+$SNAP/include \
    $TC_CLK \
    $SNAP/src/cf_math_pkg.sv \
    $SNAP/src/clk_int_div.sv \
    clk_int_div_tb.sv \
    -top clk_int_div_tb 2>&1 | tee compile.log

  if [ ! -x simv ]; then
    echo "FAIL: Compilation failed."
  else
    ./simv -cm line+cond+tgl+branch+fsm 2>&1 | tee simv.log

    if grep -q "TEST PASSED" simv.log; then
      echo "PASS"
    elif grep -q "TEST FAILED" simv.log; then
      echo "FAIL"
    else
      echo "FAIL: No clear verdict found."
    fi
  fi
fi

#!/bin/bash

SNAP=../../snapshots/pulp-platform_riscv-dbg_pr89
CCELL=../../../common_cells

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  -assert svaext \
  +incdir+"$SNAP/include" \
  +incdir+"$CCELL/include" \
  "tc_clk.sv" \
  -f ../../../common_cells/filelist.f \
  "pulp_clk_cells.sv" \
  "cluster_clk_cells.sv" \
  "$SNAP/src/dm_pkg.sv" \
  "$SNAP/src/dmi_cdc.sv" \
  "$SNAP/src/dmi_jtag_tap.sv" \
  "$SNAP/src/dmi_jtag.sv" \
  tb_dmi_reset_update_gate_patch.sv \
  -top tb_dmi_reset_update_gate_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

# Check for overall pass/fail from the testbench summary
if grep -q "^PASS: All" simv.log; then
  echo "RESULT: PASS"
elif grep -q "FAIL:" simv.log; then
  echo "RESULT: FAIL"
  # Show which tests failed
  grep "\[FAIL\]" simv.log
else
  echo "RESULT: ERROR - no pass/fail summary found"
fi

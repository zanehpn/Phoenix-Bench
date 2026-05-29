#!/bin/bash

SNAP=../../snapshots/pulp-platform_riscv-dbg_pr56
CCELL=../../../common_cells

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  -assert svaext \
  +incdir+"$SNAP/include" \
  +incdir+"$CCELL/include" \
  -f ../../../common_cells/filelist.f \
  "$SNAP/src/dm_pkg.sv" \
  "$SNAP/src/dm_csrs.sv" \
  tb_dm_haltsum_reduction_patch.sv \
  -top tb_dm_haltsum_reduction_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "RESULT: ALL TESTS PASSED" simv.log; then
  echo "PASS: haltsum reductions honour odd hart-counts."
else
  echo "FAIL: haltsum reductions still incorrect."
fi

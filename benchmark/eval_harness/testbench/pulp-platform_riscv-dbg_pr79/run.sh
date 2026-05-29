#!/bin/bash

SNAP=../../snapshots/pulp-platform_riscv-dbg_pr79
CCELL=../../../common_cells

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  -assert svaext \
  +incdir+"$SNAP/include" \
  +incdir+"$CCELL/include" \
  -f ../../../common_cells/filelist.f \
  "$SNAP/src/dm_pkg.sv" \
  "$SNAP/src/dm_csrs.sv" \
  tb_dm_cmderr_busy_patch.sv \
  -top tb_dm_cmderr_busy_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "\[FAIL\]" simv.log; then
  echo "FAIL: Some tests did not pass. See simv.log for details."
elif grep -q "PASS: All tests passed" simv.log; then
  echo "PASS: All CmdErrBusy tests passed."
else
  echo "FAIL: Unexpected simulation output. See simv.log for details."
fi

#!/bin/bash

SNAP=../../snapshots/pulp-platform_riscv-dbg_pr93
CCELL=../../../common_cells

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  -assert svaext \
  +incdir+"$SNAP/include" \
  +incdir+"$CCELL/include" \
  -f ../../../common_cells/filelist.f \
  "$SNAP/src/dm_pkg.sv" \
  "$SNAP/src/dm_csrs.sv" \
  tb_dm_sbbusyerror_block_patch.sv \
  -top tb_dm_sbbusyerror_block_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "FAIL" simv.log; then
  echo "FAIL: sbaddr still updates while sbbusyerror set."
else
  echo "PASS: sbaddr respects sbbusyerror."
fi

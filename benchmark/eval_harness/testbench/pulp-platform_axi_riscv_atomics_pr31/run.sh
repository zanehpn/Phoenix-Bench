#!/bin/bash


SNAP=../../snapshots/pulp-platform_axi_riscv_atomics_pr31
CCELL=../../../common_cells

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  -assert svaext \
  +incdir+"$SNAP/include" \
  +incdir+"$CCELL/include" \
  -f ../../../common_cells/filelist.f \
  axi_pkg.sv \
  "$SNAP/src/axi_res_tbl.sv" \
  "$SNAP/src/axi_riscv_lrsc.sv" \
  tb_axi_riscv_lrsc_burst_patch.sv \
  -top tb_axi_riscv_lrsc_burst_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS: LR/SC adapter invalidates exactly" simv.log; then
  echo "PASS: LR/SC burst invalidation length is correct."
else
  echo "FAIL: LR/SC burst invalidation length still wrong."
fi

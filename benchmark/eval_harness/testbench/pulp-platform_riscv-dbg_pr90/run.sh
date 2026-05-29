#!/bin/bash

SNAP=../../snapshots/pulp-platform_riscv-dbg_pr90

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  -assert svaext \
  "$SNAP/debug_rom/debug_rom.sv" \
  "$SNAP/src/dm_pkg.sv" \
  "$SNAP/src/dm_mem.sv" \
  tb_dm_dscratch_store_patch.sv \
  -top tb_dm_dscratch_store_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS: Abstract command stores a0 in dscratch1 before reuse." simv.log; then
  echo "PASS: Abstract command preserves a0 via CSRW when sbscratch is busy."
else
  echo "FAIL: Abstract command still emits CSRR instead of CSRW."
fi

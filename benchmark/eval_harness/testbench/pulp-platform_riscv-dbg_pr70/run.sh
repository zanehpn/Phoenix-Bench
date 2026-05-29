#!/bin/bash

SNAP=../../snapshots/pulp-platform_riscv-dbg_pr70

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  -assert svaext \
  "$SNAP/src/dm_sba.sv" \
  tb_dm_sba_read_be_patch.sv \
  -top tb_dm_sba_read_be_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS: All SBA byte-enable and functionality tests passed." simv.log; then
  echo "PASS: All SBA byte-enable and functionality tests passed."
else
  echo "FAIL: Some tests did not pass. See simv.log for details."
fi

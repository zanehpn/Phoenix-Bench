#!/bin/bash

SNAP=../../snapshots/openhwgroup_cvw_pr1554

vcs -cm line+cond+tgl+branch+fsm -sverilog -full64 -debug_access+all \
  -timescale=1ns/1ps \
  +incdir+"$SNAP/config/shared" \
  "$SNAP/src/cvw.sv" \
  "$SNAP/src/generic/mux.sv" \
  "$SNAP/src/mmu/mmu.sv" \
  tb_mmu_misaligned_fault_patch.sv \
  -top tb_mmu_misaligned_fault_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS: Misaligned load raises fault even when the TLB misses without ZICCLSM support." simv.log; then
  echo "PASS: MMU prioritizes misaligned faults when ZICCLSM is disabled."
else
  echo "FAIL: MMU still mishandles misaligned faults without ZICCLSM."
fi

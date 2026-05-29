#!/bin/bash

SNAP=../../snapshots/openhwgroup_cvfpu_pr87
CCELL=../../../common_cells/

vcs -cm line+cond+tgl+branch+fsm -full64 -sverilog \
  -timescale=1ns/1ps \
  +define+TARGET_VSIM \
  -assert svaext \
  +incdir+"$CCELL/include" \
  -f ../../../common_cells/filelist.f \
  "$SNAP/src/fpnew_pkg.sv" \
  "$SNAP/src/fpnew_rounding.sv" \
  "$SNAP/src/fpnew_fma.sv" \
  "$SNAP/src/fpnew_fma_multi.sv" \
  "$SNAP/src/fpnew_cast_multi.sv" \
  "$SNAP/src/fpnew_classifier.sv" \
  "$SNAP/src/fpnew_divsqrt_multi.sv" \
  "$SNAP/src/fpnew_noncomp.sv" \
  "$SNAP/src/fpnew_opgroup_fmt_slice.sv" \
  "$SNAP/src/fpnew_opgroup_block.sv" \
  "$SNAP/src/fpnew_opgroup_multifmt_slice.sv" \
  "$SNAP/src/fpnew_top.sv" \
  tb_fpnew_multifmt_c_operand_patch.sv \
  -top tb_fpnew_multifmt_c_operand_patch \
  -full64 -debug_access+all

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS:" simv.log; then
  echo "PASS: Multi-format slice correctly handles the third operand lanes."
else
  echo "FAIL: Multi-format slice still corrupts third operand lanes."
fi

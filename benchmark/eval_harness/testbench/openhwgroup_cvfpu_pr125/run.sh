#!/bin/bash

SNAP=../../snapshots/openhwgroup_cvfpu_pr125
CCELL=../../../common_cells/

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
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
  tb_fpnew_cast_status_patch.sv \
  -top tb_fpnew_cast_status_patch \
  -full64 -debug_access+all

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS: I2F conversions raise OF without triggering NV." simv.log; then
  echo "PASS: CVFPU reports overflow correctly on I2F conversions."
else
  echo "FAIL: CVFPU still misreports overflow on I2F casts."
fi

#!/bin/bash


SRC=../../snapshots/openhwgroup_cv32e40s_pr259/rtl

vcs -cm line+cond+tgl+branch+fsm -sverilog \
  $SRC/include/cv32e40s_pkg.sv \
  $SRC/cv32e40s_pmp.sv \
  tb_cv32e40s_pmp_mml_patch.sv \
  -top tb_cv32e40s_pmp_mml_patch \
  -full64 -debug_access+all

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS: All PMP tests passed." simv.log; then
  echo "RESULT: PASS"
else
  echo "RESULT: FAIL"
fi

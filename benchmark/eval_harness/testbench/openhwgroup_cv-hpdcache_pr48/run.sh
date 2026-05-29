#!/bin/bash

vcs -cm line+cond+tgl+branch+fsm -sverilog \
  ../../snapshots/openhwgroup_cv-hpdcache_pr48/rtl/src/hpdcache_ctrl_pe.sv \
  tb_hpdcache_evt_write_patch.sv \
  -top tb_hpdcache_evt_write_patch \
  -full64 -debug_access+all

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS:" simv.log; then
  echo "PASS: Write event fix detected."
else
  echo "FAIL: Write event fix missing."
fi

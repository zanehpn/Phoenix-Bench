#!/bin/bash

vcs -cm line+cond+tgl+branch+fsm -sverilog \
  -timescale=1ns/1ps \
  ../../snapshots/openhwgroup_cv-hpdcache_pr33/rtl/src/hpdcache_ctrl_pe.sv \
  hpdcache_ctrl_pe_new.sv \
  tb_hpdcache_prefetch_plru_patch.sv \
  -top tb_hpdcache_prefetch_plru_patch \

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "^PASS: All" simv.log; then
  echo "PASS: PLRU prefetch patch tests passed."
elif grep -q "^FAIL:" simv.log; then
  echo "FAIL: PLRU prefetch patch tests failed."
else
  echo "FAIL: Simulation did not produce expected output."
fi


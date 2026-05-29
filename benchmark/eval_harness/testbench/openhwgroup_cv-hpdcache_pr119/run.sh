#!/bin/bash

PKG=../../snapshots/openhwgroup_cv-hpdcache_pr119/rtl/src/target/cva6/cva6_op_hpdcache_params_pkg.sv

if ! vcs -sverilog "$PKG" tb_hpdcache_params_pkg_patch.sv \
  -top tb_hpdcache_params_pkg_patch -full64 -debug_access+all; then
  echo "FAIL: hpdcache_params_pkg failed to compile (likely missing semicolon)."
fi

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS:" simv.log; then
  echo "PASS: hpdcache parameters package builds successfully."
else
  echo "FAIL: Simulation did not report success."
fi

#!/bin/bash

vcs -cm line+cond+tgl+branch+fsm -sverilog tb_otbn_env_cov_mnemonic_bins_patch.sv -top tb_otbn_env_cov_mnemonic_bins_patch \
  -full64 -debug_access+all

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS:" simv.log; then
  echo "PASS: Coverage macros reverted to variable-based bins."
else
  echo "FAIL: Coverage macros still broken."
fi

#!/bin/bash
cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  tb_pulp_soc_license_patch.sv \
  -top tb_pulp_soc_license_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS: tcdm_arbiter_2x1.sv carries the Solderpad license header with no confidential text." simv.log; then
  echo "PASS: License header updated to Solderpad."
else
  echo "FAIL: Confidential license text still present."

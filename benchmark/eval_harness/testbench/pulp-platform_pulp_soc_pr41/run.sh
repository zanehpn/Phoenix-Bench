#!/bin/bash
vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  tb_pulp_soc_l2_interleave_patch.sv \
  -top tb_pulp_soc_l2_interleave_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS: Interleaved L2 SRAM removes byte+bank bits from the address." simv.log; then
  echo "PASS: L2 interleaved address slicing updated."
else
  echo "FAIL: L2 interleaved banks still alias due to missing address bits."
fi

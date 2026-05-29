#!/bin/bash

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  tb_pulp_soc_axi_id_width_patch.sv \
  -top tb_pulp_soc_axi_id_width_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS: pulp_soc.sv configures slave/in AXI buses with AXI_ID_IN_WIDTH." simv.log; then
  echo "PASS: pulp_soc AXI ID widths corrected."
else
  echo "FAIL: pulp_soc AXI ID widths still mismatched."
fi

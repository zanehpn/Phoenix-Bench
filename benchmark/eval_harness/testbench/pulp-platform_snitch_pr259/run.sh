#!/bin/bash

vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog tb_occamy_axi_lite_bridge_patch.sv -top tb_occamy_axi_lite_bridge_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log

if grep -q "PASS: Occamy AXI-Lite crossbar exposes SOC output and connects back into the narrow AXI fabric." simv.log; then
  echo "PASS: AXI-Lite SBA bridge present in occamy sources."
else
  echo "FAIL: AXI-Lite SBA bridge still missing."
fi

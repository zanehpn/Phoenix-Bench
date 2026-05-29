#!/bin/bash
SNAP=../../snapshots/pulp-platform_tech_cells_generic_pr30
TB=tb_tc_sram_byte_enable_patch.sv
TC_FILE="$SNAP/src/fpga/tc_sram_xilinx.sv"
LOG=simv.log
LOG1=compile.log
vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog -assert svaext +define+TARGET_SYNTHESIS "$TB" "$TC_FILE" -top tb_tc_sram_byte_enable_patch | tee "$LOG1"
./simv -cm line+cond+tgl+branch+fsm | tee "$LOG"

if grep -q "Error" "$LOG1"; then
  echo "FAIL: tc_sram byte-enable replication still broken."
else
  echo "PASS: tc_sram byte-enable fix detected."
fi

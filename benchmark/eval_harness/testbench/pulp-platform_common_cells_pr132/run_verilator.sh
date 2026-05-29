#!/bin/bash
TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
cd "$TESTBENCH_DIR"
set -o pipefail
__SIMV_RC=0
rm -rf obj_dir verilator.log simv.log verilator_build.log

verilator --binary --timing --Wno-fatal \
  --Wno-WIDTH --Wno-UNOPTFLAT --Wno-BLKANDNBLK --Wno-CASEINCOMPLETE \
  --Wno-UNUSEDSIGNAL --Wno-UNUSEDPARAM --Wno-SELRANGE --Wno-IMPLICIT \
  --Wno-MULTIDRIVEN --Wno-LATCH --Wno-STMTDLY --Wno-REALCVT \
  --timescale 1ns/1ps \
  tb_common_cells_clk_int_div_shift.sv \
  --top-module tb_common_cells_clk_int_div_shift \
  -o simv_vlt 2>&1 | tee verilator_build.log

if [ ! -x obj_dir/simv_vlt ]; then exit 1; fi
./obj_dir/simv_vlt 2>&1 | tee simv.log
__SIMV_RC=${PIPESTATUS[0]}
exit "$__SIMV_RC"

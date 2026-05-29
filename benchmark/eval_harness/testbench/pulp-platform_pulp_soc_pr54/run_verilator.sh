#!/bin/bash
TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
cd "$TESTBENCH_DIR"
set -o pipefail
__SIMV_RC=0
rm -rf obj_dir verilator.log simv.log verilator_build.log
verilator --binary --timing --Wno-fatal --timescale 1ns/1ps \
  tb_lint_jtag_wrap_verilator.sv --top-module adbg_lintonly_top \
  -o simv_vlt 2>&1 | tee verilator_build.log
if [ ! -x obj_dir/simv_vlt ]; then exit 1; fi
./obj_dir/simv_vlt 2>&1 | tee simv.log
__SIMV_RC=${PIPESTATUS[0]}
exit "$__SIMV_RC"

#!/bin/bash
set -u
TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
REPO_ROOT="$(cd "$TESTBENCH_DIR/../.." && pwd)"
SNAPSHOT="$REPO_ROOT/snapshots/lowRISC_opentitan_pr28469"
cd "$TESTBENCH_DIR"
set -o pipefail

rm -rf obj_dir verilator_build.log simv.log

verilator --binary --timing --Wno-fatal \
  --Wno-WIDTH --Wno-UNOPTFLAT --Wno-BLKANDNBLK --Wno-CASEINCOMPLETE \
  --Wno-UNUSEDSIGNAL --Wno-UNUSEDPARAM --Wno-SELRANGE --Wno-IMPLICIT \
  --Wno-MULTIDRIVEN --Wno-LATCH --Wno-STMTDLY --Wno-DECLFILENAME \
  --timescale 1ns/1ps \
  "$SNAPSHOT/hw/top_darjeeling/ip_autogen/pinmux/rtl/pinmux.sv" \
  tb_pinmux_sys_reset_verilator.sv \
  --top-module tb_pinmux_sys_reset \
  -o simv_vlt 2>&1 | tee verilator_build.log

if [ ! -x obj_dir/simv_vlt ]; then
  echo "FAIL: Verilator build failed." >&2
  exit 1
fi

./obj_dir/simv_vlt 2>&1 | tee simv.log
exit "${PIPESTATUS[0]}"

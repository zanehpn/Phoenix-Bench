#!/bin/bash
TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
SNAP="${TESTBENCH_DIR}/../../snapshots/pulp-platform_common_cells_pr170"
cd "$TESTBENCH_DIR"
set -o pipefail
__SIMV_RC=0

rm -rf obj_dir verilator.log simv.log verilator_build.log

# If patched source doesn't exist, this triggers build failure.
verilator --binary --timing --Wno-fatal \
  --Wno-WIDTH --Wno-UNOPTFLAT --Wno-BLKANDNBLK --Wno-CASEINCOMPLETE \
  --Wno-UNUSEDSIGNAL --Wno-UNUSEDPARAM --Wno-SELRANGE --Wno-IMPLICIT \
  --Wno-MULTIDRIVEN --Wno-LATCH --Wno-STMTDLY --Wno-REALCVT \
  --timescale 1ns/1ps \
  -y "${SNAP}/src" -y "${SNAP}/include/common_cells" +incdir+"${SNAP}/include" \
  tb_shift_reg_gated_patch.sv \
  --top-module tb_shift_reg_gated_patch \
  -o simv_vlt 2>&1 | tee verilator_build.log

if [ ! -x obj_dir/simv_vlt ]; then
  echo "FAIL: Verilator build failed (shift_reg_gated missing)." >&2
  exit 1
fi

./obj_dir/simv_vlt 2>&1 | tee simv.log
__SIMV_RC=${PIPESTATUS[0]}
exit "$__SIMV_RC"

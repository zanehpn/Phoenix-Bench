#!/bin/bash
# Auto-generated Verilator runner (converted from run.sh).
# Pass/fail is still determined by PASS:/FAIL: text in the log.
# Note: complex run.sh scripts with loops/multi-config VCS calls
# are flattened here — only the first VCS invocation is emulated.

TESTBENCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd)"
cd "$TESTBENCH_DIR"

rm -rf obj_dir

verilator \
  --binary \
  --timing \
  --Wno-fatal \
  --Wno-WIDTH --Wno-UNOPTFLAT --Wno-BLKANDNBLK --Wno-CASEINCOMPLETE \
  --Wno-UNUSEDSIGNAL --Wno-UNUSEDPARAM --Wno-SELRANGE --Wno-IMPLICIT \
  --Wno-MULTIDRIVEN --Wno-LATCH --Wno-STMTDLY --Wno-REALCVT \
  --Wno-ENUMVALUE --Wno-PINMISSING --Wno-ASCRANGE \
  --Wno-CASEX --Wno-WIDTHCONCAT --Wno-MODDUP \
  --Wno-ASSIGNIN --Wno-VARHIDDEN --Wno-DECLFILENAME \
  --Wno-COMBDLY --Wno-IGNOREDRETURN --Wno-LITENDIAN \
  --timescale 1ns/1ps \
  -y ../../snapshots/pulp-platform_common_cells_pr155/src \
  ../../snapshots/pulp-platform_common_cells_pr155/src/cb_filter_pkg.sv \
  ../../snapshots/pulp-platform_common_cells_pr155/src/cdc_reset_ctrlr_pkg.sv \
  ../../snapshots/pulp-platform_common_cells_pr155/src/cf_math_pkg.sv \
  ../../snapshots/pulp-platform_common_cells_pr155/src/ecc_pkg.sv \
  ../../snapshots/pulp-platform_common_cells_pr155/src/fifo_v3.sv \
  ../../snapshots/pulp-platform_common_cells_pr155/src/fall_through_register.sv \
  tb_common_cells_fall_through_register_patch_verilator.sv \
  --top-module tb_common_cells_fall_through_register_patch \
  -o simv_vlt 2>&1 | tee verilator_build.log

if [ ! -x obj_dir/simv_vlt ]; then
  echo "FAIL: Verilator build failed." >&2
  exit 1
fi

# Wrap obj_dir/simv_vlt so any `./simv ...` or `${SIMV_NAME}` in
# the preserved shell block writes to verilator.log / simv.log.

set -o pipefail
__SIMV_RC=0
# ---- rewritten run.sh body (vcs/simv substituted) ----
#!/bin/bash

SNAP="../../snapshots/pulp-platform_common_cells_pr155"

# Compile using the snapshot's fall_through_register.sv (buggy: uses fifo_v2)
# and only fifo_v3.sv. The buggy code references fifo_v2 which is not provided,
# so compilation should fail. The patched code uses fifo_v3 directly.
: # [verilator-rewrite] dropped vcs invocation

./obj_dir/simv_vlt 2>&1 | tee simv.log
__SIMV_RC=${PIPESTATUS[0]}

[ -f simv.log ] || cp -f verilator.log simv.log 2>/dev/null || true
exit "$__SIMV_RC"

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
  tb_pulp_soc_axi_id_width_patch_verilator.sv \
  --top-module tb_pulp_soc_axi_id_width_patch \
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

: # [verilator-rewrite] dropped vcs invocation

./obj_dir/simv_vlt | tee simv.log
__SIMV_RC=${PIPESTATUS[0]}

[ -f simv.log ] || cp -f verilator.log simv.log 2>/dev/null || true
exit "$__SIMV_RC"

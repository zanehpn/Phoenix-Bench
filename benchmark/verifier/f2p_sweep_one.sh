#!/bin/bash
# Run one instance's run_verilator.sh, emit a single CSV row.
# Args: $1 = instance directory name
# Env:  SWEEP_CSV (output csv), SWEEP_LOGDIR (per-instance logs)
set -u
NAME="$1"
TB_ROOT="/workspace/phoenix-bench/HDL_verified_new/testbench_verilator"
TB_DIR="$TB_ROOT/$NAME"
CSV="${SWEEP_CSV:-/workspace/phoenix-bench/HDL_verified_new/f2p_full_sweep_2026-05-27.csv}"
LOGDIR="${SWEEP_LOGDIR:-/workspace/phoenix-bench/HDL_verified_new/f2p_full_sweep_2026-05-27_logs}"
TIMEOUT_S="${SWEEP_TIMEOUT:-600}"

mkdir -p "$LOGDIR"
LOG="$LOGDIR/$NAME.log"

if [ ! -d "$TB_DIR" ]; then
    flock "$CSV" -c "echo \"$NAME,NA,NA,NA,MISSING_DIR\" >> \"$CSV\""
    exit 0
fi
if [ ! -f "$TB_DIR/run_verilator.sh" ]; then
    flock "$CSV" -c "echo \"$NAME,NA,NA,NA,MISSING_RUN_SH\" >> \"$CSV\""
    exit 0
fi

start=$(date +%s)
timeout "$TIMEOUT_S" bash "$TB_DIR/run_verilator.sh" > "$LOG" 2>&1
rc=$?
elapsed=$(($(date +%s) - start))

# Parse buggy:X fixed:Y line
bf=$(grep -oE 'buggy:[0-9-]+ fixed:[0-9-]+' "$LOG" | tail -1)
buggy_rc=$(echo "$bf" | sed -nE 's/.*buggy:([0-9-]+).*/\1/p')
fixed_rc=$(echo "$bf" | sed -nE 's/.*fixed:([0-9-]+).*/\1/p')
buggy_rc=${buggy_rc:-NA}
fixed_rc=${fixed_rc:-NA}

# Verdict
if [ "$rc" -eq 124 ]; then
    verdict="TIMEOUT"
elif grep -qE "^PASS: $NAME$" "$LOG"; then
    verdict="PASS"
elif grep -qE "^FAIL: $NAME$" "$LOG"; then
    verdict="FAIL"
elif [ "$rc" -eq 0 ]; then
    verdict="PASS"
else
    verdict="ERROR_RC${rc}"
fi

flock "$CSV" -c "echo \"$NAME,$rc,$buggy_rc,$fixed_rc,$verdict,${elapsed}s\" >> \"$CSV\""

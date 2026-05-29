#!/bin/bash
# usage: run_and_log.sh <case_name>
# Runs the candidate harness for one case (single compile + verification),
# then atomically appends a row to results.tsv based on candidate_run.log.
set -u
NAME="${1:?usage: run_and_log.sh <case_name>}"
ROOT="/workspace/phoenix-bench/HDL_agent_eval/benchmark_eda"
TB="$ROOT/testbench_verilator/$NAME"
RUNS="$ROOT/agent_runs"
LOGDIR="$RUNS/logs"
RESULTS="$RUNS/results.tsv"

mkdir -p "$LOGDIR"

if [ ! -d "$TB" ]; then
  printf "%s\t%s\t%s\t%s\n" "$(date -Iseconds)" "$NAME" "ERROR" "missing_testbench" \
    | flock "$RESULTS.lock" tee -a "$RESULTS" >/dev/null
  exit 2
fi

cd "$TB"
# wipe stale logs so we can read the freshest result
rm -f candidate_run.log candidate_run.err
# 10-minute hard cap; verilator builds for these RTL packs are usually < 2 min
timeout 600 bash run_candidate.sh > "$LOGDIR/$NAME.stdout" 2> "$LOGDIR/$NAME.stderr"
rc=$?
# Mirror stdout to candidate_run.log so the gate below can inspect last lines.
cp -f "$LOGDIR/$NAME.stdout" "$TB/candidate_run.log" 2>/dev/null || true

status="UNKNOWN"
notes=""
if [ -f "$TB/candidate_run.log" ] && tail -3 "$TB/candidate_run.log" | grep -q "^PASS:"; then
  status="PASS"
elif [ "$rc" -eq 124 ]; then
  status="TIMEOUT"
  notes="exceeded 600s"
else
  status="FAIL"
  # capture last interesting line for triage
  last=$(tail -3 "$TB/candidate_run.log" 2>/dev/null | tr '\n' ' ' | tr '\t' ' ')
  notes="rc=$rc ${last}"
fi

printf "%s\t%s\t%s\t%s\n" "$(date -Iseconds)" "$NAME" "$status" "$notes" \
  | flock "$RESULTS.lock" tee -a "$RESULTS" >/dev/null

echo "$NAME -> $status"
[ "$status" = PASS ] && exit 0 || exit 1

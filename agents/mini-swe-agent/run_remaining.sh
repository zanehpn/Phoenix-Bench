#!/bin/bash
cd /workspace/phoenix-bench/agents/mini-swe-agent
export OPENAI_API_KEY="YOUR_OPENAI_API_KEY"
export OPENAI_API_BASE="https://api.openai.com/v1"
export MODEL="gpt-5.2"

for i in $(seq 1 20); do
  missing=0
  for case in $(ls /workspace/phoenix-bench/HDL_verified_new/issues/); do
    [ -d "/workspace/phoenix-bench/HDL_verified_new/snapshots/$case" ] || continue
    [ -f "results_hdl/$case/result.json" ] || missing=$((missing+1))
  done
  echo "[loop $i] missing=$missing"
  [ "$missing" -eq 0 ] && break
  timeout 3600 python3 run_hdl_batch.py >> results_hdl_loop.log 2>&1
  # Mark any case that was being processed when timeout hit
  last=$(grep "\[batch\] ====" results_hdl_loop.log | tail -1 | sed 's/.*==== //' | sed 's/ ====.*//')
  if [ -n "$last" ] && [ ! -f "results_hdl/$last/result.json" ]; then
    mkdir -p "results_hdl/$last"
    echo "{\"case_name\":\"$last\",\"status\":\"error\",\"error\":\"timeout/hang\"}" > "results_hdl/$last/result.json"
    echo "[loop $i] marked $last as error"
  fi
done
echo "[loop] done"

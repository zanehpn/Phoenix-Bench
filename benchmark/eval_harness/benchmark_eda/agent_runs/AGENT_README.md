# Per-Agent Workflow

You are processing a queue of HDL bug-fix cases. Each case has:
- **Issue description**: `/workspace/phoenix-bench/HDL_agent_eval/benchmark_eda/issues/<NAME>` (plain markdown, may include the PR comments that hint at the fix)
- **Buggy source tree**: `/workspace/phoenix-bench/HDL_agent_eval/benchmark_eda/snapshots/<NAME>/` — modify files here directly
- **Verification harness**: `/workspace/phoenix-bench/HDL_agent_eval/benchmark_eda/testbench_verilator/<NAME>/`
  - `run_verilator.sh` lists `SOURCES=( … snapshot_scratch/… )` — the snapshot-side files in `SOURCES` are the ones that matter; everything else can be ignored.
  - `tb_*.sv` is the reference testbench (read-only, do **not** modify).

## Per-case loop

For each `NAME` in your batch file:

1. `cat /workspace/phoenix-bench/HDL_agent_eval/benchmark_eda/issues/$NAME` to read the bug description.
2. `grep -E '\$HERE/snapshot_scratch' /workspace/phoenix-bench/HDL_agent_eval/benchmark_eda/testbench_verilator/$NAME/run_verilator.sh` to find the snapshot files in scope.
3. Open those files under `snapshots/$NAME/…` and figure out the bug from the issue text + the testbench. Apply a focused fix with the **Edit** tool (no scope-creep cleanup).
4. `bash /workspace/phoenix-bench/HDL_agent_eval/benchmark_eda/agent_runs/run_and_log.sh $NAME` — this performs **one** compile+sim and atomically records PASS/FAIL/TIMEOUT to `agent_runs/results.tsv`.
5. If it FAILed: peek at `agent_runs/logs/$NAME.stdout` (last 60 lines) and `testbench_verilator/$NAME/verilator_fixed_build.log` for the error. You get **one** retry: adjust the fix, re-run `run_and_log.sh`. Do not iterate more than twice.
6. If still failing or you can't determine the fix within ~8 minutes, mark it skipped:
   ```
   printf "%s\t%s\tSKIP\t%s\n" "$(date -Iseconds)" "$NAME" "<short reason>" | flock /workspace/phoenix-bench/HDL_agent_eval/benchmark_eda/agent_runs/results.tsv.lock tee -a /workspace/phoenix-bench/HDL_agent_eval/benchmark_eda/agent_runs/results.tsv >/dev/null
   ```
   and move on.

## Hard rules

- **Never** edit files under `testbench_verilator/`. The testbench is the oracle.
- **Never** modify files outside `snapshots/$NAME/` for that case.
- Do **not** apply gold patches, do **not** touch git, do **not** run more than one compile+sim per attempt (the helper enforces this).
- If the snapshot already PASSes on first run, that's fine — record it and move on.
- Keep your output terse. Don't echo file contents back into the conversation; rely on tool reads.

## Reading helpers

- Snapshot file: `Read` tool on `/workspace/phoenix-bench/HDL_agent_eval/benchmark_eda/snapshots/<NAME>/<path>`
- Testbench reference: `Read` on `/workspace/phoenix-bench/HDL_agent_eval/benchmark_eda/testbench_verilator/<NAME>/tb_*.sv`
- Verilator build log (after a failed run): `/workspace/phoenix-bench/HDL_agent_eval/benchmark_eda/testbench_verilator/<NAME>/verilator_fixed_build.log`
- Verilator sim log: `/workspace/phoenix-bench/HDL_agent_eval/benchmark_eda/testbench_verilator/<NAME>/verilator_fixed.log`

## Memory discipline

You are one of 5 parallel agents. Avoid spawning extra parallel verilator runs yourself — `run_and_log.sh` is single-shot by design.

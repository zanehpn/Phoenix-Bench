#!/usr/bin/env python3
"""Run mini-swe-agent on Phoenix-bench (benchmark_4) with gpt-5.1."""

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = "/workspace/phoenix-bench/HDL_agent_eval/benchmark_4"
ISSUES_DIR = os.path.join(ROOT, "issues")
SNAPSHOTS_DIR = os.path.join(ROOT, "snapshots")
OUT_ROOT = "/workspace/phoenix-bench/agents/mini-swe-agent/results_benchmark4"
PROGRESS_LOG = "/workspace/phoenix-bench/agents/mini-swe-agent/results_benchmark4_progress.log"

MODEL = os.environ.get("MODEL", "gpt-5.2")
COST_LIMIT = float(os.environ.get("COST_LIMIT", "3.0"))
PER_CASE_TIMEOUT = int(os.environ.get("PER_CASE_TIMEOUT", "300"))

os.environ["OPENAI_API_KEY"] = "YOUR_OPENAI_API_KEY"
os.environ["OPENAI_API_BASE"] = "https://api.openai.com/v1"


def log_progress(line: str):
    with open(PROGRESS_LOG, "a") as f:
        f.write(line + "\n")
    print(line, flush=True)


def run_one_case(case_name: str) -> dict:
    issue_file = os.path.join(ISSUES_DIR, case_name)
    snapshot_dir = os.path.join(SNAPSHOTS_DIR, case_name)
    case_out = os.path.join(OUT_ROOT, case_name)
    os.makedirs(case_out, exist_ok=True)

    issue_text = Path(issue_file).read_text(errors="ignore").strip()

    work_dir = os.path.join(case_out, "work_snapshot")
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir)
    # symlinks=True: preserve symlinks instead of dereferencing them.
    # Some snapshots have recursive symlinks (e.g. example/*/lib/pcie -> ../../rtl)
    # that expand 8MB → 30GB+ if dereferenced.
    shutil.copytree(snapshot_dir, work_dir, symlinks=True, ignore_dangling_symlinks=True)

    if not os.path.isdir(os.path.join(work_dir, ".git")):
        subprocess.run(["git", "init"], cwd=work_dir, capture_output=True)
        subprocess.run(["git", "add", "-A"], cwd=work_dir, capture_output=True)
        subprocess.run(["git", "-c", "user.name=init", "-c", "user.email=init@local",
                        "commit", "-m", "initial"], cwd=work_dir, capture_output=True)

    case_patch_target = os.path.join(case_out, "agent_patch.diff")
    task = (
        f"Fix the following HDL/SystemVerilog bug in the repository at {work_dir}.\n\n"
        f"Issue:\n{issue_text}\n\n"
        f"Instructions:\n"
        f"1. The repository is at: {work_dir}\n"
        f"2. Analyze the issue, find the relevant files, and make minimal code changes to fix the bug.\n"
        f"3. Only modify source files (.sv, .v, .svh, .vh etc), do NOT modify testbenches.\n"
        f"4. After fixing, run: cd {work_dir} && git diff > {case_patch_target}\n"
        f"5. Then submit with: echo COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT\n"
    )

    cmd = [
        sys.executable, "-m", "minisweagent.run.hello_world",
        "--task", task,
        "--model", MODEL,
    ]
    env = os.environ.copy()
    env["MSWEA_MODEL_NAME"] = MODEL
    env["PYTHONPATH"] = "/workspace/phoenix-bench/agents/mini-swe-agent/src"
    # Quiet litellm debug spam to keep stderr from filling pipes
    env["LITELLM_LOG"] = "WARNING"

    stdout_path = os.path.join(case_out, "stdout.log")
    stderr_path = os.path.join(case_out, "stderr.log")

    t0 = time.time()
    timeout_hit = False
    rc = None
    try:
        with open(stdout_path, "w") as so, open(stderr_path, "w") as se:
            proc = subprocess.Popen(
                cmd, env=env, stdout=so, stderr=se,
                text=True, cwd=OUT_ROOT,
                start_new_session=True,  # new process group for clean kill
            )
            try:
                rc = proc.wait(timeout=PER_CASE_TIMEOUT)
            except subprocess.TimeoutExpired:
                # kill the entire process group (mini-swe-agent + any tool subshells)
                try:
                    os.killpg(proc.pid, 9)
                except ProcessLookupError:
                    pass
                proc.wait(timeout=10)
                rc = -9
                timeout_hit = True
    except Exception as e:
        with open(stderr_path, "a") as se:
            se.write(f"\n[launch_error] {e}\n")
        rc = -1
    wall = time.time() - t0
    stdout = ""  # we wrote directly to file
    stderr = ""  # we wrote directly to file

    patch_proc = subprocess.run(
        ["git", "diff"], cwd=work_dir, capture_output=True, text=True
    )
    patch = patch_proc.stdout.strip()

    if patch:
        Path(os.path.join(case_out, "final_changes.patch")).write_text(patch + "\n")
        if timeout_hit:
            status = "completed_timeout"
        else:
            status = "completed"
    else:
        Path(os.path.join(case_out, "final_changes.patch")).write_text("")
        if timeout_hit:
            status = "timeout_no_patch"
        elif rc != 0:
            status = "no_patch_error"
        else:
            status = "no_patch"

    result = {
        "case_name": case_name,
        "status": status,
        "patch_size": len(patch),
        "wall_seconds": round(wall, 1),
        "model": MODEL,
        "returncode": rc,
        "timeout_seconds": PER_CASE_TIMEOUT,
    }
    Path(os.path.join(case_out, "result.json")).write_text(json.dumps(result, indent=2))

    shutil.rmtree(work_dir, ignore_errors=True)
    return result


def main():
    cases = sorted([
        c for c in os.listdir(ISSUES_DIR)
        if os.path.isfile(os.path.join(ISSUES_DIR, c))
        and os.path.isdir(os.path.join(SNAPSHOTS_DIR, c))
    ])
    os.makedirs(OUT_ROOT, exist_ok=True)
    log_progress(f"[batch] start total={len(cases)} model={MODEL} timeout={PER_CASE_TIMEOUT}s")

    for i, case_name in enumerate(cases, 1):
        result_file = os.path.join(OUT_ROOT, case_name, "result.json")
        if os.path.isfile(result_file):
            try:
                prev = json.load(open(result_file))
                if prev.get("status", "").startswith(("completed", "no_patch", "timeout")):
                    log_progress(f"[skip] {i}/{len(cases)} {case_name} prev_status={prev.get('status')}")
                    continue
            except Exception:
                pass

        try:
            result = run_one_case(case_name)
        except Exception as e:
            result = {"case_name": case_name, "status": "harness_error", "error": str(e)}
            log_progress(f"[harness_error] {i}/{len(cases)} {case_name}: {e}")
            continue

        log_progress(f"[done] {i}/{len(cases)} {case_name} "
                     f"status={result['status']} patch={result['patch_size']} "
                     f"wall={result.get('wall_seconds')}s rc={result.get('returncode')}")

    log_progress("[batch] all cases processed")


if __name__ == "__main__":
    main()

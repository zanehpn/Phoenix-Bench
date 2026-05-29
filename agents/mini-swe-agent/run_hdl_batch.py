#!/usr/bin/env python3
"""Run mini-swe-agent on HDL_verified_new dataset."""

import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

HDL_ROOT = "/workspace/phoenix-bench/HDL_verified_new"
ISSUES_DIR = os.path.join(HDL_ROOT, "issues")
SNAPSHOTS_DIR = os.path.join(HDL_ROOT, "snapshots")
OUT_ROOT = "/workspace/phoenix-bench/agents/mini-swe-agent/results_hdl"
MODEL = os.environ.get("MODEL", "gpt-5.2")
COST_LIMIT = float(os.environ.get("COST_LIMIT", "3.0"))

# API config
os.environ["OPENAI_API_KEY"] = "YOUR_OPENAI_API_KEY"
os.environ["OPENAI_API_BASE"] = "https://api.openai.com/v1"


def run_one_case(case_name: str) -> dict:
    issue_file = os.path.join(ISSUES_DIR, case_name)
    snapshot_dir = os.path.join(SNAPSHOTS_DIR, case_name)
    case_out = os.path.join(OUT_ROOT, case_name)
    os.makedirs(case_out, exist_ok=True)

    # Read issue
    issue_text = Path(issue_file).read_text(errors="ignore").strip()

    # Create a working copy of the snapshot
    work_dir = os.path.join(case_out, "work_snapshot")
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir)
    shutil.copytree(snapshot_dir, work_dir)

    # Init git if needed
    if not os.path.isdir(os.path.join(work_dir, ".git")):
        subprocess.run(["git", "init"], cwd=work_dir, capture_output=True)
        subprocess.run(["git", "add", "-A"], cwd=work_dir, capture_output=True)
        subprocess.run(["git", "-c", "user.name=init", "-c", "user.email=init@local",
                         "commit", "-m", "initial"], cwd=work_dir, capture_output=True)

    # Build task description
    task = (
        f"Fix the following HDL/SystemVerilog bug in the repository at {work_dir}.\n\n"
        f"Issue:\n{issue_text}\n\n"
        f"Instructions:\n"
        f"1. The repository is at: {work_dir}\n"
        f"2. Analyze the issue, find the relevant files, and make minimal code changes to fix the bug.\n"
        f"3. Only modify source files (.sv, .v, .svh, .vh etc), do NOT modify testbenches.\n"
        f"4. After fixing, run: cd {work_dir} && git diff > /tmp/patch.diff\n"
        f"5. Then submit with: echo COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT\n"
    )

    traj_file = os.path.join(case_out, "trajectory.json")

    # Run mini-swe-agent
    cmd = [
        sys.executable, "-m", "minisweagent.run.hello_world",
        "--task", task,
        "--model", MODEL,
    ]

    env = os.environ.copy()
    env["MSWEA_MODEL_NAME"] = MODEL

    try:
        proc = subprocess.Popen(
            cmd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, cwd=OUT_ROOT,
        )
        stdout, stderr = proc.communicate(timeout=300)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
        stdout = ""
        stderr = "timeout after 300s - killed"
    except Exception as e:
        stdout = ""
        stderr = str(e)

    # Extract patch from working dir
    patch_proc = subprocess.run(
        ["git", "diff"], cwd=work_dir, capture_output=True, text=True
    )
    patch = patch_proc.stdout.strip()

    # Save results
    Path(os.path.join(case_out, "stdout.log")).write_text(stdout)
    Path(os.path.join(case_out, "stderr.log")).write_text(stderr)

    if patch:
        Path(os.path.join(case_out, "final_changes.patch")).write_text(patch + "\n")
        status = "completed"
    else:
        Path(os.path.join(case_out, "final_changes.patch")).write_text("")
        status = "no_patch"

    result = {
        "case_name": case_name,
        "status": status,
        "patch_size": len(patch),
    }
    Path(os.path.join(case_out, "result.json")).write_text(json.dumps(result, indent=2))

    # Clean work_snapshot to save disk
    shutil.rmtree(work_dir, ignore_errors=True)

    return result


def main():
    cases = sorted([
        c for c in os.listdir(ISSUES_DIR)
        if os.path.isfile(os.path.join(ISSUES_DIR, c))
        and os.path.isdir(os.path.join(SNAPSHOTS_DIR, c))
    ])

    print(f"[batch] total_cases={len(cases)} model={MODEL}", flush=True)
    os.makedirs(OUT_ROOT, exist_ok=True)

    for case_name in cases:
        result_file = os.path.join(OUT_ROOT, case_name, "result.json")
        if os.path.isfile(result_file):
            prev = json.load(open(result_file))
            if prev.get("status") in ("completed", "no_patch"):
                print(f"[skip] {case_name}", flush=True)
                continue

        print(f"\n[batch] ==== {case_name} ====", flush=True)
        try:
            result = run_one_case(case_name)
        except Exception as e:
            result = {"case_name": case_name, "status": "error", "error": str(e)}
            print(f"[error] {case_name}: {e}", flush=True)

        print(f"[done] {case_name}: {result.get('status')} patch={result.get('patch_size', 0)}", flush=True)

    print("\n[batch] all cases processed", flush=True)


if __name__ == "__main__":
    main()

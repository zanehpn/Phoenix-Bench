#!/usr/bin/env python3
import os, json, subprocess, sys, shutil
from pathlib import Path

HDL_ROOT = "/workspace/phoenix-bench/HDL_verified_new"
ISSUES_DIR = os.path.join(HDL_ROOT, "issues")
SNAPSHOTS_DIR = os.path.join(HDL_ROOT, "snapshots")
OUT_ROOT = "/workspace/phoenix-bench/agents/mini-swe-agent/results_hdl"
MODEL = "gpt-5.2"

os.environ["OPENAI_API_KEY"] = "YOUR_OPENAI_API_KEY"
os.environ["OPENAI_API_BASE"] = "https://api.openai.com/v1"
os.environ["MSWEA_MODEL_NAME"] = MODEL

cases = sorted([c for c in os.listdir(ISSUES_DIR)
    if os.path.isfile(os.path.join(ISSUES_DIR, c))
    and os.path.isdir(os.path.join(SNAPSHOTS_DIR, c))])

for case_name in cases:
    result_file = os.path.join(OUT_ROOT, case_name, "result.json")
    if os.path.isfile(result_file):
        prev = json.load(open(result_file))
        if prev.get("status") in ("completed", "error"):
            continue
    print(f"[run] {case_name}", flush=True)
    case_out = os.path.join(OUT_ROOT, case_name)
    os.makedirs(case_out, exist_ok=True)
    work_dir = os.path.join(case_out, "work_snapshot")
    if os.path.exists(work_dir):
        shutil.rmtree(work_dir)
    shutil.copytree(os.path.join(SNAPSHOTS_DIR, case_name), work_dir)
    if not os.path.isdir(os.path.join(work_dir, ".git")):
        subprocess.run(["git", "init"], cwd=work_dir, capture_output=True)
        subprocess.run(["git", "add", "-A"], cwd=work_dir, capture_output=True)
        subprocess.run(["git", "-c", "user.name=init", "-c", "user.email=init@local", "commit", "-m", "initial"], cwd=work_dir, capture_output=True)
    issue_text = Path(os.path.join(ISSUES_DIR, case_name)).read_text(errors="ignore").strip()
    task = (f"Fix the following HDL/SystemVerilog bug in the repository at {work_dir}.\n\n"
            f"Issue:\n{issue_text}\n\n"
            f"Instructions:\n1. The repository is at: {work_dir}\n"
            f"2. Only modify source files (.sv, .v, .svh, .vh etc).\n"
            f"3. After fixing, run: cd {work_dir} && git diff > /tmp/patch.diff\n"
            f"4. Then submit: echo COMPLETE_TASK_AND_SUBMIT_FINAL_OUTPUT\n")
    cmd = [sys.executable, "-m", "minisweagent.run.hello_world", "--task", task, "--model", MODEL]
    try:
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, cwd=OUT_ROOT)
        stdout, stderr = proc.communicate(timeout=300)
    except subprocess.TimeoutExpired:
        proc.kill()
        try: proc.wait(timeout=10)
        except: pass
        stdout, stderr = "", "timeout-killed"
    except Exception as e:
        stdout, stderr = "", str(e)
    try:
        patch = subprocess.run(["git", "diff"], cwd=work_dir, capture_output=True, text=True, timeout=10).stdout.strip()
    except:
        patch = ""
    Path(os.path.join(case_out, "stdout.log")).write_text(stdout or "")
    Path(os.path.join(case_out, "stderr.log")).write_text(stderr or "")
    status = "completed" if patch else ("error" if "timeout" in (stderr or "") else "no_patch")
    Path(os.path.join(case_out, "final_changes.patch")).write_text((patch + "\n") if patch else "")
    Path(os.path.join(case_out, "result.json")).write_text(json.dumps({"case_name": case_name, "status": status, "patch_size": len(patch)}, indent=2))
    shutil.rmtree(work_dir, ignore_errors=True)
    print(f"[done] {case_name}: {status} patch={len(patch)}", flush=True)
print("[ALL DONE]", flush=True)

#!/usr/bin/env python3

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import textwrap
from datetime import datetime
from typing import Dict, List, Optional


ISSUES_DIR = "/workspace/phoenix-bench/HDL_verified_new/issues"
SNAPSHOTS_DIR = "/workspace/phoenix-bench/HDL_verified_new/snapshots"
TESTBENCH_DIR = "/workspace/phoenix-bench/HDL_verified_new/testbench"
API_KEY_SOURCE = "/workspace/phoenix-bench/Agentless_backup/run_agentless.sh"
DOCKER_TESTBENCH = "/workspace/phoenix-bench/Local_agent/docker_testbench_agent.py"
ISSUE_GRAPH_AGENT = "/workspace/phoenix-bench/Local_agent/issue_graph_agent.py"
DEFAULT_OUT_ROOT = "/workspace/phoenix-bench/aider_test"
DEFAULT_MODEL = "gpt-5.2"
DEFAULT_API_BASE = "https://api.openai.com/v1"
DEFAULT_EXTRA_REPO_DIRS = [
    "/workspace/phoenix-bench/common_cells",
    "/workspace/phoenix-bench/common_verification",
    "/workspace/phoenix-bench/tech_cells_generic",
    "/workspace/phoenix-bench/pulp_cluster",
]


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def read_text(path: str) -> str:
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def write_text(path: str, text: str) -> None:
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def read_json(path: str) -> Dict[str, object]:
    with open(path, "r", encoding="utf-8") as f:
        obj = json.load(f)
    if not isinstance(obj, dict):
        raise RuntimeError(f"invalid json object: {path}")
    return obj


def run_cmd(
    cmd: List[str],
    *,
    cwd: Optional[str] = None,
    env: Optional[Dict[str, str]] = None,
    timeout: Optional[int] = None,
    log_path: Optional[str] = None,
    check: bool = True,
) -> subprocess.CompletedProcess:
    proc = subprocess.run(
        cmd,
        cwd=cwd,
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if log_path:
        write_text(
            log_path,
            f"$ {' '.join(cmd)}\n\n[stdout]\n{proc.stdout}\n\n[stderr]\n{proc.stderr}\n",
        )
    if check and proc.returncode != 0:
        raise RuntimeError(
            f"command failed rc={proc.returncode}: {' '.join(cmd)}\n"
            f"stdout:\n{proc.stdout[-4000:]}\n"
            f"stderr:\n{proc.stderr[-4000:]}"
        )
    return proc


def tail_lines(text: str, n: int = 20) -> str:
    lines = [line.rstrip() for line in (text or "").splitlines() if line.strip()]
    return "\n".join(lines[-n:]) if lines else ""


def load_api_key(path: str) -> str:
    text = read_text(path)
    match = re.search(r"^export\s+OPENAI_API_KEY=(.+)$", text, flags=re.MULTILINE)
    if not match:
        raise RuntimeError(f"OPENAI_API_KEY not found in {path}")
    return match.group(1).strip()


def safe_copytree(src: str, dst: str, ignore=None) -> None:
    if os.path.exists(dst):
        shutil.rmtree(dst)
    shutil.copytree(src, dst, ignore=ignore)


def copy_extra_repo_dirs(work_repo: str, extra_repo_dirs: List[str]) -> None:
    for src in extra_repo_dirs:
        src = os.path.normpath(src)
        if not os.path.isdir(src):
            raise RuntimeError(f"missing extra repo dir: {src}")
        dst = os.path.join(work_repo, os.path.basename(src))
        safe_copytree(src, dst)


def prepare_workspace(case_name: str, case_root: str, extra_repo_dirs: List[str]) -> Dict[str, str]:
    src_issue = os.path.join(ISSUES_DIR, case_name)
    src_snapshot = os.path.join(SNAPSHOTS_DIR, case_name)
    src_testbench = os.path.join(TESTBENCH_DIR, case_name)
    if not os.path.isfile(src_issue):
        raise RuntimeError(f"missing issue file: {src_issue}")
    if not os.path.isdir(src_snapshot):
        raise RuntimeError(f"missing snapshot dir: {src_snapshot}")
    if not os.path.isdir(src_testbench):
        raise RuntimeError(f"missing testbench dir: {src_testbench}")

    run_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_root = os.path.join(case_root, "runs", run_id)
    ensure_dir(run_root)

    work_repo = os.path.join(run_root, "work_repo")
    issue_dst = os.path.join(work_repo, "HDL_verified_new", "issues", case_name)
    snapshot_dst = os.path.join(work_repo, "HDL_verified_new", "snapshots", case_name)
    testbench_dst = os.path.join(work_repo, "HDL_verified_new", "testbench", case_name)
    ensure_dir(os.path.dirname(issue_dst))
    ensure_dir(os.path.dirname(snapshot_dst))
    ensure_dir(os.path.dirname(testbench_dst))

    shutil.copy2(src_issue, issue_dst)
    safe_copytree(src_snapshot, snapshot_dst)
    safe_copytree(
        src_testbench,
        testbench_dst,
        ignore=shutil.ignore_patterns(
            "csrc",
            "simv",
            "simv.daidir",
            "ucli.key",
            "*.log",
            "*.vpd",
            "DVEfiles",
        ),
    )
    copy_extra_repo_dirs(work_repo, extra_repo_dirs)

    return {
        "run_root": run_root,
        "work_repo": work_repo,
        "issue_file": issue_dst,
        "snapshot_dir": snapshot_dst,
        "testbench_dir": testbench_dst,
    }


def init_git_repo(repo_dir: str, log_dir: str) -> None:
    run_cmd(["git", "init"], cwd=repo_dir, log_path=os.path.join(log_dir, "git_init.log"))
    run_cmd(["git", "config", "user.name", "Aider Test"], cwd=repo_dir)
    run_cmd(["git", "config", "user.email", "aider-test@example.com"], cwd=repo_dir)
    run_cmd(["git", "add", "-A"], cwd=repo_dir)
    run_cmd(
        ["git", "commit", "-m", "baseline snapshot"],
        cwd=repo_dir,
        log_path=os.path.join(log_dir, "git_commit.log"),
    )


def run_issue_graph_agent(
    repo_dir: str,
    issue_file: str,
    iter_dir: str,
    extra_repo_dirs: List[str],
) -> Dict[str, object]:
    outdir = os.path.join(iter_dir, "issue_graph")
    result_json = os.path.join(iter_dir, "issue_graph_result.json")
    cmd = [
        sys.executable,
        ISSUE_GRAPH_AGENT,
        "--repo",
        repo_dir,
        "--issue_file",
        issue_file,
        "--outdir",
        outdir,
        "--result_out",
        result_json,
        "--allow_selection_fallback",
    ]
    for extra_repo in extra_repo_dirs:
        cmd.extend(["--incdir", os.path.join(repo_dir, os.path.basename(os.path.normpath(extra_repo)))])
    proc = run_cmd(
        cmd,
        log_path=os.path.join(iter_dir, "issue_graph_command.log"),
        check=False,
        timeout=1800,
    )
    if proc.returncode != 0 or not os.path.isfile(result_json):
        raise RuntimeError(
            "issue_graph_agent failed\n"
            f"stdout:\n{tail_lines(proc.stdout)}\n"
            f"stderr:\n{tail_lines(proc.stderr)}"
        )
    return read_json(result_json)


def extract_selected_files(issue_graph_result: Dict[str, object], max_files: int = 8) -> List[str]:
    out: List[str] = []
    final_selection = issue_graph_result.get("final_selection") or {}
    if isinstance(final_selection, dict):
        rows = final_selection.get("selected_files") or []
        if isinstance(rows, list):
            for row in rows:
                if not isinstance(row, dict):
                    continue
                file_path = row.get("file")
                if isinstance(file_path, str) and file_path not in out:
                    out.append(file_path)
                if len(out) >= max_files:
                    return out
    retrieval = issue_graph_result.get("retrieval") or {}
    if isinstance(retrieval, dict):
        rows = retrieval.get("top_files") or []
        if isinstance(rows, list):
            for row in rows:
                if not isinstance(row, dict):
                    continue
                file_path = row.get("file")
                if isinstance(file_path, str) and file_path not in out:
                    out.append(file_path)
                if len(out) >= max_files:
                    return out
    return out


def make_first_prompt(issue_text: str, allowed_files: List[str], run_sh_text: str) -> str:
    files_text = "\n".join(f"- {path}" for path in allowed_files)
    return textwrap.dedent(
        f"""\
        You are editing a copied HDL repository in an isolated experiment workspace.

        Goal:
        Fix the bug described below with the minimal code change needed so the docker testbench can pass.

        Constraints:
        - Edit only the files listed below.
        - Do not modify the testbench.
        - Keep the change minimal and production-quality.
        - Do not add comments unless required.

        Allowed files:
        {files_text}

        Relevant testbench:
        ```bash
        {run_sh_text.strip()}
        ```

        Issue:
        {issue_text.strip()}
        """
    )


def make_feedback_prompt(
    issue_text: str,
    allowed_files: List[str],
    run_sh_text: str,
    feedback: str,
    log_tail: str,
) -> str:
    files_text = "\n".join(f"- {path}" for path in allowed_files)
    return textwrap.dedent(
        f"""\
        You already attempted a fix, and the docker testbench still does not pass.

        Revise the existing change based on the test feedback below.

        Constraints:
        - Edit only the files listed below.
        - Do not modify the testbench.
        - Keep the change minimal.
        - Focus on the actual compile/runtime failure shown by the feedback.

        Allowed files:
        {files_text}

        Relevant testbench:
        ```bash
        {run_sh_text.strip()}
        ```

        Original issue:
        {issue_text.strip()}

        Testbench feedback summary:
        {feedback.strip() if feedback.strip() else "(no issue_snippet captured)"}

        Tail of combined test log:
        ```text
        {log_tail.strip()}
        ```
        """
    )


def run_aider_once(
    repo_dir: str,
    allowed_files: List[str],
    prompt_path: str,
    iter_dir: str,
    model: str,
    api_base: str,
    api_key: str,
) -> Dict[str, object]:
    env = os.environ.copy()
    env["AIDER_MODEL"] = model
    env["AIDER_OPENAI_API_BASE"] = api_base
    env["AIDER_OPENAI_API_KEY"] = api_key

    cmd = [
        "aider",
        "--model",
        model,
        "--yes-always",
        "--no-auto-commits",
        "--no-dirty-commits",
        "--no-check-update",
        "--no-show-model-warnings",
        "--map-tokens",
        "0",
        "--no-pretty",
        "--no-stream",
        "--no-detect-urls",
        "--message-file",
        prompt_path,
        "--chat-history-file",
        os.path.join(iter_dir, "aider_chat.md"),
        "--llm-history-file",
        os.path.join(iter_dir, "aider_llm.jsonl"),
        "--input-history-file",
        os.path.join(iter_dir, "aider_input.history"),
    ]
    cmd.extend(allowed_files)
    proc = run_cmd(
        cmd,
        cwd=repo_dir,
        env=env,
        log_path=os.path.join(iter_dir, "aider_command.log"),
        check=False,
    )
    diff_proc = run_cmd(
        ["git", "diff", "--", *allowed_files],
        cwd=repo_dir,
        log_path=os.path.join(iter_dir, "git_diff.log"),
        check=False,
    )
    return {
        "returncode": proc.returncode,
        "stdout_tail": proc.stdout[-4000:],
        "stderr_tail": proc.stderr[-4000:],
        "diff_nonempty": bool(diff_proc.stdout.strip()),
    }


def tail_text(path: str, max_chars: int = 4000) -> str:
    if not os.path.isfile(path):
        return ""
    text = read_text(path)
    return text[-max_chars:]


def patch_touched_files(patch_text: str) -> List[str]:
    out: List[str] = []
    for line in patch_text.splitlines():
        if line.startswith("+++ b/"):
            rel = line[6:].strip()
            if rel and rel != "/dev/null" and rel not in out:
                out.append(rel)
    return out


def infer_pass_from_test_log(log_file: str) -> Dict[str, object]:
    text = read_text(log_file) if log_file and os.path.isfile(log_file) else ""
    pass_marker = "PASS:"
    fail_marker = "FAIL:"
    actual_pass = pass_marker in text and fail_marker not in text
    actual_fail = fail_marker in text
    return {
        "actual_pass": actual_pass,
        "actual_fail": actual_fail,
        "pass_marker_found": pass_marker in text,
        "fail_marker_found": fail_marker in text,
        "log_tail": text[-4000:],
    }


def run_testbench(host_repo: str, case_name: str, iter_dir: str, container_prefix: str) -> Dict[str, object]:
    ensure_dir(os.path.join(iter_dir, "test_logs"))
    summary_json = os.path.join(iter_dir, "test_summary.json")
    summary_csv = os.path.join(iter_dir, "test_summary.csv")
    cmd = [
        sys.executable,
        DOCKER_TESTBENCH,
        "--host_repo",
        host_repo,
        "--testbench_subdir",
        "HDL_verified_new/testbench",
        "--case",
        case_name,
        "--timeout_sec",
        "1800",
        "--no-interactive",
        "--heartbeat_sec",
        "20",
        "--print_issue_lines",
        "--issue_max_lines",
        "20",
        "--container_prefix",
        container_prefix,
        "--log_dir",
        os.path.join(iter_dir, "test_logs"),
        "--summary_json",
        summary_json,
        "--summary_csv",
        summary_csv,
    ]
    proc = run_cmd(
        cmd,
        log_path=os.path.join(iter_dir, "testbench_command.log"),
        check=False,
        timeout=2100,
    )
    summary: Dict[str, object] = {}
    if os.path.isfile(summary_json):
        summary = read_json(summary_json)
    records = summary.get("records") or []
    record = records[0] if records else {}
    log_file = str(record.get("log_file", ""))
    actual = infer_pass_from_test_log(log_file)
    return {
        "returncode": proc.returncode,
        "status": record.get("status", "missing"),
        "issue_snippet": record.get("issue_snippet", ""),
        "log_file": log_file,
        "summary_json": summary_json,
        "summary_csv": summary_csv,
        "stdout_tail": proc.stdout[-4000:],
        "stderr_tail": proc.stderr[-4000:],
        "actual_pass": actual["actual_pass"],
        "actual_fail": actual["actual_fail"],
        "pass_marker_found": actual["pass_marker_found"],
        "fail_marker_found": actual["fail_marker_found"],
        "log_tail": actual["log_tail"],
    }


def export_final_patch(repo_dir: str, allowed_files: List[str], run_root: str) -> str:
    patch_path = os.path.join(run_root, "final.patch")
    proc = run_cmd(
        ["git", "diff", "--", *allowed_files],
        cwd=repo_dir,
        log_path=os.path.join(run_root, "final_diff.log"),
        check=False,
    )
    write_text(patch_path, proc.stdout)
    return patch_path


def main() -> None:
    ap = argparse.ArgumentParser(description="Run isolated aider + docker testbench loop for one HDL case.")
    ap.add_argument("--case", default="pulp-platform_common_cells_pr192")
    ap.add_argument("--out-root", default=DEFAULT_OUT_ROOT)
    ap.add_argument("--model", default=DEFAULT_MODEL)
    ap.add_argument("--api-base", default=DEFAULT_API_BASE)
    ap.add_argument("--extra-repo-dirs", nargs="*", default=list(DEFAULT_EXTRA_REPO_DIRS))
    args = ap.parse_args()

    case_root = os.path.join(args.out_root, args.case)
    ensure_dir(case_root)
    paths = prepare_workspace(args.case, case_root, args.extra_repo_dirs)
    run_root = paths["run_root"]
    logs_dir = os.path.join(run_root, "logs")
    ensure_dir(logs_dir)

    snapshot_repo = paths["snapshot_dir"]
    issue_text = read_text(paths["issue_file"])
    run_sh_text = read_text(os.path.join(paths["testbench_dir"], "run.sh"))
    api_key = load_api_key(API_KEY_SOURCE)

    metadata = {
        "case": args.case,
        "run_root": run_root,
        "model": args.model,
        "api_base": args.api_base,
        "api_key_source": API_KEY_SOURCE,
        "extra_repo_dirs": args.extra_repo_dirs,
    }
    write_text(os.path.join(run_root, "run_config.json"), json.dumps(metadata, indent=2))

    init_git_repo(snapshot_repo, logs_dir)
    bootstrap = run_issue_graph_agent(
        repo_dir=snapshot_repo,
        issue_file=paths["issue_file"],
        iter_dir=logs_dir,
        extra_repo_dirs=args.extra_repo_dirs,
    )
    allowed_files = extract_selected_files(bootstrap, max_files=8)
    if not allowed_files:
        raise RuntimeError("issue_graph_agent returned no candidate files")

    status: Dict[str, object] = {
        "case": args.case,
        "run_root": run_root,
        "selected_files": allowed_files,
        "issue_graph_result": os.path.join(logs_dir, "issue_graph_result.json"),
        "attempts": [],
    }

    iter1_dir = os.path.join(run_root, "iter_1")
    ensure_dir(iter1_dir)
    prompt1 = make_first_prompt(issue_text, allowed_files, run_sh_text)
    prompt1_path = os.path.join(iter1_dir, "prompt.txt")
    write_text(prompt1_path, prompt1)
    aider1 = run_aider_once(
        repo_dir=snapshot_repo,
        allowed_files=allowed_files,
        prompt_path=prompt1_path,
        iter_dir=iter1_dir,
        model=args.model,
        api_base=args.api_base,
        api_key=api_key,
    )
    test1 = run_testbench(
        host_repo=paths["work_repo"],
        case_name=args.case,
        iter_dir=iter1_dir,
        container_prefix=f"tb-aider-{datetime.now().strftime('%H%M%S')}-1",
    )
    status["attempts"].append({"iteration": 1, "aider": aider1, "testbench": test1})

    final_status = str(test1.get("status", "missing"))
    final_actual_status = "pass" if bool(test1.get("actual_pass")) else "fail"
    if final_actual_status != "pass":
        iter2_dir = os.path.join(run_root, "iter_2")
        ensure_dir(iter2_dir)
        log_tail = tail_text(str(test1.get("log_file", "")))
        prompt2 = make_feedback_prompt(
            issue_text=issue_text,
            allowed_files=allowed_files,
            run_sh_text=run_sh_text,
            feedback=str(test1.get("issue_snippet", "")),
            log_tail=log_tail,
        )
        prompt2_path = os.path.join(iter2_dir, "prompt.txt")
        write_text(prompt2_path, prompt2)
        aider2 = run_aider_once(
            repo_dir=snapshot_repo,
            allowed_files=allowed_files,
            prompt_path=prompt2_path,
            iter_dir=iter2_dir,
            model=args.model,
            api_base=args.api_base,
            api_key=api_key,
        )
        test2 = run_testbench(
            host_repo=paths["work_repo"],
            case_name=args.case,
            iter_dir=iter2_dir,
            container_prefix=f"tb-aider-{datetime.now().strftime('%H%M%S')}-2",
        )
        status["attempts"].append({"iteration": 2, "aider": aider2, "testbench": test2})
        final_status = str(test2.get("status", "missing"))
        final_actual_status = "pass" if bool(test2.get("actual_pass")) else "fail"

    patch_path = export_final_patch(snapshot_repo, allowed_files, run_root)
    patch_text = read_text(patch_path)
    status["final_status"] = final_status
    status["final_actual_status"] = final_actual_status
    status["final_patch"] = patch_path
    status["touched_files"] = patch_touched_files(patch_text)
    status["patched_files_in_repo"] = [os.path.join(snapshot_repo, path) for path in allowed_files]
    write_text(os.path.join(run_root, "status.json"), json.dumps(status, indent=2))
    print(json.dumps(status, indent=2))


if __name__ == "__main__":
    main()

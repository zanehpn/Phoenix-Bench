#!/usr/bin/env python3
"""
Run ExpeRepair on HDL_verified_new dataset.
Pipeline: localize (find bug files/lines) → generate (write patch without test)
"""

import argparse
import json
import os
import sys
from pathlib import Path

EXPE_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "ExpeRepair-v1.0")
sys.path.insert(0, EXPE_DIR)

from raw_tasks import RawLocalTask
from model import common
from model.register import register_all_models
from search.search_manage import SearchManager
from agents.agent_write_patch import PatchAgent
from data_structures import BugLocation, MessageThread
from log import print_banner
from agentless_utils import show_project_structure
from repo_structure.preprocess_data import get_repo_structure

HDL_ROOT = "/workspace/phoenix-bench/HDL_verified_new"
ISSUES_DIR = os.path.join(HDL_ROOT, "issues")
SNAPSHOTS_DIR = os.path.join(HDL_ROOT, "snapshots")


def get_hdl_repo_structure(repo_path: str) -> str:
    """Get directory structure for an HDL repo. Paths are relative to repo_path."""
    lines = []
    for root, dirs, files in os.walk(repo_path):
        dirs[:] = [d for d in dirs if not d.startswith('.') and d not in {'__pycache__', 'node_modules', '.git'}]
        rel = os.path.relpath(root, repo_path)
        if rel == '.':
            rel = ''
        level = rel.count(os.sep) if rel else 0
        indent = ' ' * 2 * level
        dir_name = os.path.basename(root) if rel else '.'
        lines.append(f"{indent}{dir_name}/")
        subindent = ' ' * 2 * (level + 1)
        for f in sorted(files):
            ext = os.path.splitext(f)[1].lower()
            if ext in {'.sv', '.svh', '.v', '.vh', '.f', '.tcl', '.py', '.sh', '.mk', '.yaml', '.yml', '.json', '.md', '.txt', '.cpp', '.c', '.h'}:
                lines.append(f"{subindent}{f}")
    return '\n'.join(lines[:500])


def run_one_case(case_name, args):
    """Run localize + generate for one case."""
    issue_file = os.path.join(ISSUES_DIR, case_name)
    snapshot_dir = os.path.join(SNAPSHOTS_DIR, case_name)
    case_output = os.path.join(args.output_folder, case_name)
    os.makedirs(case_output, exist_ok=True)

    # Create task
    raw_task = RawLocalTask(
        task_id=case_name,
        local_repo=snapshot_dir,
        issue_file=issue_file,
    )
    task = raw_task.to_task()
    task._task_id = case_name

    # Get repo structure
    repo_struct = get_hdl_repo_structure(snapshot_dir)

    # === Step 1: Localize ===
    print_banner(f"LOCALIZE {case_name}")
    localize_dir = os.path.join(case_output, "localize")
    os.makedirs(localize_dir, exist_ok=True)

    search_manager = SearchManager(task.project_path, os.path.abspath(localize_dir))

    # Empty reproduce result (we skip reproduce for HDL)
    empty_reproduce = {"test": "", "test_result": ""}

    bug_locs_list = search_manager.search_locations(task, repo_struct, empty_reproduce)

    # Save localization results
    written_bug_locs = []
    for bug_locs in bug_locs_list:
        written_bug_locs.append([loc.to_dict() for loc in bug_locs])
    with open(os.path.join(localize_dir, "bug_locations.json"), "w") as f:
        json.dump({"instance_id": case_name, "bug_locs": written_bug_locs}, f, indent=2)

    if not bug_locs_list or not bug_locs_list[0]:
        return {"case_name": case_name, "status": "no_locs", "error": "no bug locations found"}

    # Use BugLocation objects directly from search_locations
    bug_locations = bug_locs_list[0]

    # === Step 2: Generate patch ===
    print_banner(f"GENERATE PATCH {case_name}")
    generate_dir = os.path.join(case_output, "generate")
    os.makedirs(generate_dir, exist_ok=True)

    # Create meta.json needed by patch_utils.convert_response_to_diff
    raw_task.dump_meta_data(generate_dir)

    issue_text = Path(issue_file).read_text(errors="ignore")

    # Get the search conversation thread from localize
    context_thread = MessageThread()
    context_thread.add_system(f"You are a bug-fixing agent for HDL/SystemVerilog code in repo {case_name}.")
    context_thread.add_user(f"Issue:\n{issue_text[:3000]}")

    patch_agent = PatchAgent(
        task=task,
        search_manager=search_manager,
        issue_stmt=issue_text,
        context_thread=context_thread,
        bug_locs=bug_locations,
        task_dir=generate_dir,
    )

    try:
        handle, patches, responses = patch_agent.write_multiple_patch_wo_memory_wo_test(
            retries=3, patch_nums=4
        )
    except Exception as e:
        return {"case_name": case_name, "status": "generate_failed", "error": str(e)}

    # Save patches
    all_patches = []
    for i, (patch, response) in enumerate(zip(patches, responses)):
        patch_file = os.path.join(generate_dir, f"patch_{i}.diff")
        Path(patch_file).write_text(patch)
        all_patches.append({"index": i, "patch_file": patch_file, "patch": patch})

    # Save best patch (first applicable)
    best_patch = patches[0] if patches else ""
    Path(os.path.join(case_output, "final_patch.diff")).write_text(best_patch)

    return {
        "case_name": case_name,
        "status": "completed",
        "num_patches": len(patches),
        "bug_locs": written_bug_locs,
    }


def main():
    parser = argparse.ArgumentParser(description="Run ExpeRepair on HDL dataset")
    parser.add_argument("--model", default="gpt-5.2")
    parser.add_argument("--output_folder", default="/workspace/phoenix-bench/agents/ExpeRepair/results_hdl")
    parser.add_argument("--task_id", default=None)
    parser.add_argument("--no_skip_existing", action="store_true")
    args = parser.parse_args()

    os.environ["OPENAI_KEY"] = "YOUR_OPENAI_API_KEY"
    os.environ["OPENAI_API_KEY"] = "YOUR_OPENAI_API_KEY"
    os.environ["OPENAI_API_BASE"] = "https://api.openai.com/v1"

    register_all_models()
    common.set_model(args.model)
    common.set_gpto4_model()
    common.set_gpto3_model()

    cases = sorted([
        c for c in os.listdir(ISSUES_DIR)
        if os.path.isfile(os.path.join(ISSUES_DIR, c))
        and os.path.isdir(os.path.join(SNAPSHOTS_DIR, c))
    ])

    print(f"[batch] total_cases={len(cases)} model={args.model}")

    for case_name in cases:
        if args.task_id and args.task_id != case_name:
            continue

        result_file = os.path.join(args.output_folder, case_name, "result.json")
        if not args.no_skip_existing and os.path.isfile(result_file):
            prev = json.load(open(result_file))
            if prev.get("status") in ("completed", "no_locs", "generate_failed"):
                print(f"[skip] {case_name}")
                continue

        print(f"\n[batch] ==== {case_name} ====", flush=True)
        # Reset snapshot before each case (in case previous run left it dirty)
        snap = os.path.join(SNAPSHOTS_DIR, case_name)
        try:
            import subprocess
            subprocess.run(["git", "checkout", "."], cwd=snap, capture_output=True, timeout=30)
            subprocess.run(["git", "clean", "-fd"], cwd=snap, capture_output=True, timeout=30)
        except Exception:
            pass
        try:
            result = run_one_case(case_name, args)
        except BaseException as e:
            result = {"case_name": case_name, "status": "error", "error": str(e)}
            print(f"[error] {case_name}: {e}", flush=True)
        finally:
            # Always restore snapshot after each case
            try:
                subprocess.run(["git", "checkout", "."], cwd=snap, capture_output=True, timeout=30)
                subprocess.run(["git", "clean", "-fd"], cwd=snap, capture_output=True, timeout=30)
            except Exception:
                pass

        os.makedirs(os.path.join(args.output_folder, case_name), exist_ok=True)
        with open(result_file, "w") as f:
            json.dump(result, f, indent=2)
        print(f"[done] {case_name}: {result.get('status')}")

    print("\n[batch] all cases processed")


if __name__ == "__main__":
    main()

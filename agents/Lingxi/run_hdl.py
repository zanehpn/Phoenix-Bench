#!/usr/bin/env python3
"""
Batch runner: use Lingxi to generate patches for HDL_verified_new issues.

For each issue:
1. Copy snapshot to a temp working directory (to avoid polluting originals)
2. Initialize Lingxi RuntimeConfig pointing to the working copy
3. Feed the issue text into the supervisor graph
4. Extract the generated patch (git diff)
5. Save patch and verify against testbench
"""

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import uuid
import traceback
from pathlib import Path

# ── paths ──────────────────────────────────────────────────────────────
HDL_ROOT = "/workspace/phoenix-bench/HDL_verified_new"
ISSUES_DIR = os.path.join(HDL_ROOT, "issues")
SNAPSHOTS_DIR = os.path.join(HDL_ROOT, "snapshots")
PATCHES_DIR = os.path.join(HDL_ROOT, "patches")
TB_DIR = os.path.join(HDL_ROOT, "testbench")

OUTPUT_DIR = "/workspace/phoenix-bench/agents/Lingxi/results_hdl"
WORK_DIR = "/workspace/phoenix-bench/agents/Lingxi/workdir_hdl"

# ── environment ────────────────────────────────────────────────────────
# Set env BEFORE importing Lingxi modules (they read env at import time)
os.environ.setdefault("LANGSMITH_TRACING", "false")

# Use .env if present
from dotenv import load_dotenv
env_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
if os.path.isfile(env_file):
    load_dotenv(env_file)

# ── Lingxi imports ─────────────────────────────────────────────────────
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "src"))


def discover_cases():
    """Return sorted list of case names that have both an issue file and snapshot dir."""
    cases = []
    for name in sorted(os.listdir(ISSUES_DIR)):
        issue_path = os.path.join(ISSUES_DIR, name)
        snap_path = os.path.join(SNAPSHOTS_DIR, name)
        if os.path.isfile(issue_path) and os.path.isdir(snap_path):
            cases.append(name)
    return cases


def prepare_work_copy(case_name):
    """Copy snapshot into a git-initialised work directory. Returns work path."""
    snap_src = os.path.join(SNAPSHOTS_DIR, case_name)
    work_dst = os.path.join(WORK_DIR, case_name)

    # Clean previous run
    if os.path.exists(work_dst):
        shutil.rmtree(work_dst)

    shutil.copytree(snap_src, work_dst, symlinks=True)

    # Ensure it is a proper git repo with all files committed
    git_dir = os.path.join(work_dst, ".git")
    if os.path.isdir(git_dir):
        # Already a git repo — reset and ensure clean state
        subprocess.run(["git", "reset", "--hard"], cwd=work_dst,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["git", "clean", "-xdf"], cwd=work_dst,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        subprocess.run(["git", "init"], cwd=work_dst,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    # Always ensure all files are committed so git diff works
    subprocess.run(["git", "add", "-A"], cwd=work_dst,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["git", "-c", "user.email=test@test.com", "-c", "user.name=test",
                    "commit", "-m", "initial", "--allow-empty"],
                   cwd=work_dst,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    return work_dst


def read_issue(case_name):
    """Read the issue description text."""
    with open(os.path.join(ISSUES_DIR, case_name), "r", encoding="utf-8") as f:
        return f.read().strip()


def run_lingxi(case_name, work_path, issue_text, timeout=600):
    """
    Run Lingxi supervisor graph on a single case.
    Returns the git diff (patch string).
    """
    # Reset RuntimeConfig singleton for each case
    from agent.runtime_config import RuntimeConfig
    RuntimeConfig.reset_instance()
    rc = RuntimeConfig.get_instance()

    # Manually initialise (bypass input_handler_node)
    rc.proj_path = work_path
    rc.proj_name = case_name.replace("_", "/", 1)  # approximate owner/repo
    rc.issue_desc = issue_text
    rc.runtime_dir = WORK_DIR
    rc.initialized = True
    from agent.runtime_config import RuntimeType
    rc.runtime_type = RuntimeType.LOCAL

    # Import graph AFTER rc is set (modules read rc at import)
    # We rebuild graph components each time because rc is a singleton
    from agent.state import CustomState

    # Create LLM with higher max_tokens for HDL (default 2048 is too low)
    from langchain_openai import ChatOpenAI
    llm = ChatOpenAI(
        model=os.environ.get("LLM_MODEL", "gpt-5.2"),
        temperature=0.0,
        max_tokens=16384,
    )
    from agent.prompt import (
        ISSUE_RESOLVE_PROBLEM_DECODER_SYSTEM_PROMPT,
        ISSUE_RESOLVE_PROBLEM_SOLVER_SYSTEM_PROMPT,
        ISSUE_RESOLVE_SOLUTION_MAPPER_SYSTEM_PROMPT,
        ISSUE_RESOLVE_SUPERVISOR_SYSTEM_PROMPT,
    )
    from agent.tool_set.sepl_tools import (
        save_git_diff, view_file_content, view_directory,
        search_files_by_keywords,
    )
    from agent.tool_set.edit_tool import str_replace_editor

    from langgraph.graph import END, START, StateGraph
    from langgraph.prebuilt import create_react_agent
    from langgraph.types import Command
    from langchain_core.messages import AIMessage, HumanMessage
    from typing import Literal
    from typing_extensions import TypedDict

    # Tools (skip search_relevant_files to avoid OpenAI embedding dependency)
    decoder_tools = [view_directory, search_files_by_keywords, view_file_content]
    mapper_tools = [view_directory, search_files_by_keywords, view_file_content]
    solver_tools = [view_directory, search_files_by_keywords, str_replace_editor]

    members = ["problem_decoder", "solution_mapper", "problem_solver"]
    options = members + ["FINISH"]

    class Router(TypedDict):
        next_agent: Literal[*options]
        thought: str

    # ── node functions ─────────────────────────────────────────────
    def supervisor_node(state: CustomState):
        messages = [
            {"role": "system", "content": ISSUE_RESOLVE_SUPERVISOR_SYSTEM_PROMPT},
        ] + state["messages"]
        response = llm.with_structured_output(Router, strict=True).invoke(messages)
        goto = response["next_agent"]
        goto = END if "FINISH" in goto else goto
        return Command(
            update={
                "messages": [
                    AIMessage(
                        content="Supervisor:\nThought: " + response["thought"]
                        + "\nNext: " + response["next_agent"] + ".",
                        name="supervisor",
                    )
                ],
                "last_agent": state.get("last_agent"),
                "next_agent": goto if goto != END else None,
            },
            goto=goto,
        )

    decoder_agent = create_react_agent(
        llm, tools=decoder_tools,
        prompt=ISSUE_RESOLVE_PROBLEM_DECODER_SYSTEM_PROMPT,
    )

    def problem_decoder_node(state: CustomState):
        result = decoder_agent.invoke(state)
        new_msgs = result["messages"][len(state["messages"]):]
        for m in new_msgs:
            if isinstance(m, AIMessage):
                m.name = "problem_decoder"
        return Command(
            update={"messages": new_msgs, "last_agent": "problem_decoder"},
            goto="supervisor",
        )

    mapper_agent = create_react_agent(
        llm, tools=mapper_tools,
        prompt=ISSUE_RESOLVE_SOLUTION_MAPPER_SYSTEM_PROMPT,
    )

    def solution_mapper_node(state: CustomState):
        result = mapper_agent.invoke(state)
        new_msgs = result["messages"][len(state["messages"]):]
        for m in new_msgs:
            if isinstance(m, AIMessage):
                m.name = "solution_mapper"
        return Command(
            update={"messages": new_msgs, "last_agent": "solution_mapper"},
            goto="supervisor",
        )

    solver_agent = create_react_agent(
        llm, tools=solver_tools,
        prompt=ISSUE_RESOLVE_PROBLEM_SOLVER_SYSTEM_PROMPT,
    )

    def problem_solver_node(state: CustomState):
        result = solver_agent.invoke(state)
        new_msgs = result["messages"][len(state["messages"]):]
        for m in new_msgs:
            if isinstance(m, AIMessage):
                m.name = "problem_solver"
        latest_patch = "Below is the latest code changes:\n" + save_git_diff()
        return Command(
            update={
                "messages": new_msgs + [
                    AIMessage(content=latest_patch.rstrip(), name="problem_solver")
                ],
                "last_agent": "problem_solver",
            },
            goto="supervisor",
        )

    # ── build graph ────────────────────────────────────────────────
    builder = StateGraph(CustomState)
    builder.add_edge(START, "supervisor")
    builder.add_node("supervisor", supervisor_node)
    builder.add_node("problem_decoder", problem_decoder_node)
    builder.add_node("solution_mapper", solution_mapper_node)
    builder.add_node("problem_solver", problem_solver_node)

    graph = builder.compile()

    # ── run ────────────────────────────────────────────────────────
    thread_config = {
        "recursion_limit": 80,
        "run_id": uuid.uuid4(),
        "configurable": {"thread_id": case_name},
    }

    initial_input = {
        "messages": [HumanMessage(content=issue_text)],
        "preset": case_name,
        "human_in_the_loop": False,
    }

    patch_content = ""
    for chunk in graph.stream(initial_input, config=thread_config, stream_mode="values"):
        if "messages" in chunk and len(chunk["messages"]) > 0:
            last_msg = chunk["messages"][-1]
            if hasattr(last_msg, "content") and hasattr(last_msg, "name"):
                print(f"  [{last_msg.name}] {last_msg.content[:120]}...")
            if (hasattr(last_msg, "name") and last_msg.name == "problem_solver"
                    and "Below is the latest code changes:" in getattr(last_msg, "content", "")):
                raw = last_msg.content.replace(
                    "Below is the latest code changes:\n", ""
                ).strip()
                if "diff --git" in raw or raw.startswith("---"):
                    patch_content = raw

    # Also try extracting from git diff directly
    if not patch_content:
        try:
            result = subprocess.run(
                ["git", "-c", "core.fileMode=false", "diff", "--no-color"],
                cwd=work_path, capture_output=True, text=True, timeout=10,
            )
            patch_content = result.stdout.strip()
        except Exception:
            pass

    return patch_content


def verify_patch(case_name, patch_content):
    """
    Apply patch to the original snapshot (copy), run testbench, return result dict.
    """
    snap_src = os.path.join(SNAPSHOTS_DIR, case_name)
    tb_path = os.path.join(TB_DIR, case_name)

    if not os.path.isdir(tb_path):
        return {"status": "no_testbench"}

    # We apply to the work copy (which already has changes from Lingxi)
    # Instead, create a fresh verify copy
    verify_dir = os.path.join(WORK_DIR, case_name + "_verify")
    if os.path.exists(verify_dir):
        shutil.rmtree(verify_dir)
    shutil.copytree(snap_src, verify_dir, symlinks=True)

    # Apply patch
    if patch_content:
        patch_file = os.path.join(verify_dir, "lingxi.patch")
        with open(patch_file, "w") as f:
            f.write(patch_content)
        result = subprocess.run(
            ["patch", "-p1", "--batch", "--fuzz=3", "-i", patch_file],
            cwd=verify_dir, capture_output=True, text=True, timeout=30,
        )
        if result.returncode != 0:
            # Try git apply
            result2 = subprocess.run(
                ["git", "apply", "--verbose", patch_file],
                cwd=verify_dir, capture_output=True, text=True, timeout=30,
            )
            if result2.returncode != 0:
                return {"status": "patch_apply_failed", "error": result.stderr[:500]}

    # Create a temp testbench directory pointing to the verify snapshot
    verify_tb = os.path.join(WORK_DIR, case_name + "_tb")
    if os.path.exists(verify_tb):
        shutil.rmtree(verify_tb)
    shutil.copytree(tb_path, verify_tb, symlinks=True)

    # Fix the run.sh to point to our verify snapshot instead of original
    run_sh = os.path.join(verify_tb, "run.sh")
    if os.path.isfile(run_sh):
        with open(run_sh, "r") as f:
            content = f.read()
        # Replace snapshot path
        content = content.replace(
            f"../../snapshots/{case_name}",
            verify_dir,
        )
        with open(run_sh, "w") as f:
            f.write(content)

    # Run testbench
    try:
        result = subprocess.run(
            ["bash", "run.sh"],
            cwd=verify_tb, capture_output=True, text=True, timeout=120,
        )
        output = result.stdout + "\n" + result.stderr
    except subprocess.TimeoutExpired:
        output = "TIMEOUT"
    except Exception as e:
        output = f"ERROR: {e}"

    # Count PASS/FAIL
    pass_count = 0
    fail_count = 0
    for line in output.split("\n"):
        stripped = line.strip()
        if stripped.startswith("PASS:") or stripped.startswith("[PASS]"):
            pass_count += 1
        elif stripped.startswith("FAIL:") or stripped.startswith("[FAIL]"):
            fail_count += 1

    return {
        "status": "completed",
        "pass_count": pass_count,
        "fail_count": fail_count,
        "resolved": pass_count > 0 and fail_count == 0,
    }


def main():
    parser = argparse.ArgumentParser(description="Run Lingxi on HDL issues")
    parser.add_argument("--task_id", default=None, help="Run specific task only")
    parser.add_argument("--skip_existing", action="store_true", default=True)
    parser.add_argument("--no_skip", action="store_true", help="Don't skip existing")
    parser.add_argument("--timeout", type=int, default=600, help="Timeout per case (s)")
    parser.add_argument("--verify_only", action="store_true",
                        help="Only verify existing patches, don't generate new ones")
    args = parser.parse_args()

    if args.no_skip:
        args.skip_existing = False

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(WORK_DIR, exist_ok=True)

    cases = discover_cases()
    print(f"[batch] Total cases: {len(cases)}")

    summary = {"total": 0, "completed": 0, "resolved": 0, "error": 0, "empty_patch": 0}

    for case_name in cases:
        if args.task_id and args.task_id != case_name:
            continue

        case_output = os.path.join(OUTPUT_DIR, case_name)
        result_file = os.path.join(case_output, "result.json")
        patch_file = os.path.join(case_output, "patch.diff")

        if args.skip_existing and os.path.isfile(result_file) and not args.verify_only:
            print(f"[skip] {case_name}")
            continue

        summary["total"] += 1
        print(f"\n{'='*60}")
        print(f"[batch] {case_name}")
        print(f"{'='*60}")

        os.makedirs(case_output, exist_ok=True)

        try:
            if not args.verify_only:
                # Step 1: Prepare
                issue_text = read_issue(case_name)
                work_path = prepare_work_copy(case_name)
                print(f"  Issue: {issue_text[:100]}...")
                print(f"  Work path: {work_path}")

                # Step 2: Run Lingxi
                patch_content = run_lingxi(case_name, work_path, issue_text, args.timeout)

                # Save patch
                with open(patch_file, "w") as f:
                    f.write(patch_content or "")

                if not patch_content:
                    print(f"  [warn] No patch generated")
                    summary["empty_patch"] += 1
            else:
                if not os.path.isfile(patch_file):
                    print(f"  [skip] No patch file for verify_only")
                    continue
                with open(patch_file, "r") as f:
                    patch_content = f.read().strip()

            # Step 3: Verify
            print(f"  [verify] Running testbench...")
            verify_result = verify_patch(case_name, patch_content)
            print(f"  [verify] {verify_result}")

            result = {
                "case_name": case_name,
                "status": "completed",
                "patch_size": len(patch_content) if patch_content else 0,
                "verify": verify_result,
            }
            summary["completed"] += 1
            if verify_result.get("resolved"):
                summary["resolved"] += 1

        except Exception as e:
            print(f"  [error] {e}")
            traceback.print_exc()
            result = {
                "case_name": case_name,
                "status": "error",
                "error": str(e),
            }
            summary["error"] += 1

        with open(result_file, "w") as f:
            json.dump(result, f, indent=2)

    # Print summary
    print(f"\n{'='*60}")
    print(f"[summary]")
    print(f"  Total processed: {summary['total']}")
    print(f"  Completed:       {summary['completed']}")
    print(f"  Resolved:        {summary['resolved']}")
    print(f"  Empty patch:     {summary['empty_patch']}")
    print(f"  Errors:          {summary['error']}")
    if summary["completed"] > 0:
        print(f"  Resolve rate:    {summary['resolved']/summary['completed']*100:.1f}%")
    print(f"{'='*60}")

    # Save summary
    summary_file = os.path.join(OUTPUT_DIR, "summary.json")
    with open(summary_file, "w") as f:
        json.dump(summary, f, indent=2)


if __name__ == "__main__":
    main()

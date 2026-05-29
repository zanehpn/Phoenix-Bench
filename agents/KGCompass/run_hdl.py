#!/usr/bin/env python3
"""
Run KGCompass (LLM-loc + repair, no KG) on HDL_verified_new dataset.

Pipeline per case:
1. LLM-based localization: give issue text + repo file list -> predict bug locations
2. Repair: give issue + located code -> generate SEARCH/REPLACE patch
3. Apply patch to snapshot copy
4. Run testbench to verify
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import traceback
import difflib
import time

# ── paths ──────────────────────────────────────────────────────────────
HDL_ROOT = "/workspace/phoenix-bench/HDL_verified_new"
ISSUES_DIR = os.path.join(HDL_ROOT, "issues")
SNAPSHOTS_DIR = os.path.join(HDL_ROOT, "snapshots")
PATCHES_DIR = os.path.join(HDL_ROOT, "patches")
TB_DIR = os.path.join(HDL_ROOT, "testbench")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "results_hdl")
WORK_DIR = os.path.join(SCRIPT_DIR, "workdir_hdl")

# ── API config ─────────────────────────────────────────────────────────
API_KEY = os.environ.get("OPENAI_API_KEY", "YOUR_OPENAI_API_KEY")
API_BASE = os.environ.get("OPENAI_API_BASE", "https://api.openai.com/v1")
MODEL_NAME = os.environ.get("MODEL_NAME", "gpt-5.2")

import openai
client = openai.OpenAI(api_key=API_KEY, base_url=API_BASE)


def _update_model(model_name):
    global MODEL_NAME
    MODEL_NAME = model_name


def llm_call(prompt, temperature=0.3, max_tokens=8192):
    """Call LLM and return response text."""
    try:
        response = client.chat.completions.create(
            model=MODEL_NAME,
            messages=[{"role": "user", "content": prompt}],
            temperature=temperature,
            max_tokens=max_tokens,
        )
        return response.choices[0].message.content
    except Exception as e:
        print(f"  [llm_error] {e}")
        return None


def discover_cases():
    cases = []
    for name in sorted(os.listdir(ISSUES_DIR)):
        issue_path = os.path.join(ISSUES_DIR, name)
        snap_path = os.path.join(SNAPSHOTS_DIR, name)
        if os.path.isfile(issue_path) and os.path.isdir(snap_path):
            cases.append(name)
    return cases


def get_repo_file_list(snap_path, extensions=('.sv', '.svh', '.v', '.vh', '.py', '.cpp', '.h')):
    """Get list of source files in the snapshot."""
    files = []
    for root, dirs, fnames in os.walk(snap_path):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for f in sorted(fnames):
            if any(f.endswith(ext) for ext in extensions):
                rel = os.path.relpath(os.path.join(root, f), snap_path)
                files.append(rel)
    return files[:500]  # limit


def read_file_content(snap_path, rel_path, max_lines=300):
    """Read file content with line numbers."""
    full = os.path.join(snap_path, rel_path)
    if not os.path.isfile(full):
        return f"File not found: {rel_path}"
    try:
        with open(full, 'r', encoding='utf-8', errors='replace') as f:
            lines = f.readlines()
        if len(lines) > max_lines:
            return ''.join(f"{i+1:4d} | {l}" for i, l in enumerate(lines[:max_lines])) + f"\n... ({len(lines)} lines total, truncated)"
        return ''.join(f"{i+1:4d} | {l}" for i, l in enumerate(lines))
    except Exception as e:
        return f"Error reading {rel_path}: {e}"


def step_localize(issue_text, snap_path, file_list):
    """LLM-based bug localization: predict which files contain the bug."""
    file_list_str = "\n".join(file_list)
    prompt = f"""You are an expert hardware engineer debugging a SystemVerilog/Verilog codebase.

Given the following bug report/issue, predict which files most likely contain the bug and need to be modified.

## Issue Description
{issue_text}

## Repository File List
{file_list_str}

Please return a JSON array of the most likely buggy files (up to 5), ordered by likelihood.
Each entry should have "file_path" and "reason" fields.

Format:
```json
[
    {{"file_path": "path/to/file.sv", "reason": "brief explanation"}},
]
```

Focus on RTL source files (.sv, .v) rather than test/documentation files.
Your response should start with ```json and end with ```.
"""
    response = llm_call(prompt, temperature=0.3, max_tokens=2048)
    if not response:
        return []

    # Parse JSON from response
    try:
        match = re.search(r'```json\s*(.*?)\s*```', response, re.DOTALL)
        if match:
            locations = json.loads(match.group(1))
        else:
            locations = json.loads(response)
        return locations
    except Exception as e:
        print(f"  [loc_parse_error] {e}")
        return []


def step_repair(issue_text, snap_path, locations):
    """Generate SEARCH/REPLACE patches for the identified locations."""
    # Read the content of identified files
    content_parts = []
    for loc in locations[:4]:  # limit to top 4 files
        fp = loc.get('file_path', '')
        content = read_file_content(snap_path, fp)
        content_parts.append(f"### {fp}\n```\n{content}\n```")

    content_all = "\n\n".join(content_parts)

    prompt = f"""We are currently solving the following issue within our repository. Here is the issue text:
--- BEGIN ISSUE ---
{issue_text}
--- END ISSUE ---

Below are some code segments, each from a relevant file. One or more of these files may contain bugs.
--- BEGIN FILE ---
{content_all}
--- END FILE ---

Please first localize the bug based on the issue statement, and then generate *SEARCH/REPLACE* edits to fix the issue.

Every *SEARCH/REPLACE* edit must use this format:
1. The file path
2. The start of search block: <<<<<<< SEARCH
3. A contiguous chunk of lines to search for in the existing source code
4. The dividing line: =======
5. The lines to replace into the source code
6. The end of the replace block: >>>>>>> REPLACE

Here is an example:

```systemverilog
### rtl/my_module.sv
<<<<<<< SEARCH
    assign result = a + b;
=======
    assign result = a + b + carry_in;
>>>>>>> REPLACE
```

IMPORTANT NOTES:
1. The SEARCH block must match the exact content from the original file
2. The REPLACE block must maintain proper indentation
3. Only include the specific lines that need to be changed
4. Wrap the edits in ```systemverilog ... ``` blocks
"""
    return llm_call(prompt, temperature=0.3, max_tokens=8192)


def apply_search_replace(snap_path, raw_output):
    """Parse SEARCH/REPLACE blocks and apply them to files."""
    if not raw_output:
        return False

    # Extract code blocks
    blocks = re.findall(r'```(?:systemverilog|verilog|python|cpp|sv)?\s*(.*?)```', raw_output, re.DOTALL)
    if not blocks:
        # Try without code fences
        blocks = [raw_output]

    applied = False
    for block in blocks:
        # Find file path and SEARCH/REPLACE
        # Pattern: ### path/to/file.sv or file path on its own line
        file_match = re.search(r'###\s*(.+\.(?:sv|svh|v|vh|py|cpp|h))', block)
        if not file_match:
            file_match = re.search(r'^(.+\.(?:sv|svh|v|vh|py|cpp|h))\s*$', block, re.MULTILINE)
        if not file_match:
            continue

        file_path = file_match.group(1).strip()
        full_path = os.path.join(snap_path, file_path)
        if not os.path.isfile(full_path):
            # Try stripping leading path components
            for root, dirs, files in os.walk(snap_path):
                if os.path.basename(file_path) in files:
                    full_path = os.path.join(root, os.path.basename(file_path))
                    break

        if not os.path.isfile(full_path):
            print(f"  [apply] File not found: {file_path}")
            continue

        # Find all SEARCH/REPLACE pairs in this block
        sr_pattern = r'<<<<<<< SEARCH\n(.*?)\n=======\n(.*?)\n>>>>>>> REPLACE'
        pairs = re.findall(sr_pattern, block, re.DOTALL)

        if not pairs:
            continue

        with open(full_path, 'r', encoding='utf-8', errors='replace') as f:
            content = f.read()

        original_content = content
        for search_str, replace_str in pairs:
            search_str = search_str.strip('\n')
            replace_str = replace_str.strip('\n')

            if search_str in content:
                content = content.replace(search_str, replace_str, 1)
            else:
                # Fuzzy match: normalize whitespace
                def norm_ws(t):
                    return "\n".join(" ".join(line.split()) for line in t.split("\n"))

                norm_search = norm_ws(search_str)
                norm_content = norm_ws(content)

                if norm_search in norm_content:
                    # Find by line
                    orig_lines = content.split("\n")
                    norm_lines = norm_content.split("\n")
                    search_norm_lines = norm_search.split("\n")

                    for i in range(len(norm_lines) - len(search_norm_lines) + 1):
                        if norm_lines[i:i+len(search_norm_lines)] == search_norm_lines:
                            orig_matched = "\n".join(orig_lines[i:i+len(search_norm_lines)])
                            content = content.replace(orig_matched, replace_str, 1)
                            break
                else:
                    print(f"  [apply] SEARCH block not found in {file_path}")

        if content != original_content:
            with open(full_path, 'w', encoding='utf-8') as f:
                f.write(content)
            applied = True
            print(f"  [apply] Patched {file_path}")

    return applied


def extract_git_diff(work_path):
    """Extract git diff from work directory."""
    try:
        r = subprocess.run(
            ["git", "-c", "core.fileMode=false", "diff", "--no-color"],
            cwd=work_path, capture_output=True, text=True, timeout=10,
        )
        return r.stdout.strip()
    except:
        return ""


def prepare_work_copy(case_name):
    snap_src = os.path.join(SNAPSHOTS_DIR, case_name)
    work_dst = os.path.join(WORK_DIR, case_name)
    if os.path.exists(work_dst):
        shutil.rmtree(work_dst)
    shutil.copytree(snap_src, work_dst, symlinks=True)

    # Ensure git repo
    git_dir = os.path.join(work_dst, ".git")
    if os.path.isdir(git_dir):
        subprocess.run(["git", "reset", "--hard"], cwd=work_dst,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    else:
        subprocess.run(["git", "init"], cwd=work_dst,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["git", "add", "-A"], cwd=work_dst,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    subprocess.run(["git", "-c", "user.email=t@t.com", "-c", "user.name=t",
                    "commit", "-m", "init", "--allow-empty"],
                   cwd=work_dst,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return work_dst


def verify_patch(case_name, patch_content):
    tb_path = os.path.join(TB_DIR, case_name)
    if not os.path.isdir(tb_path):
        return {"status": "no_testbench"}

    snap_src = os.path.join(SNAPSHOTS_DIR, case_name)
    verify_dir = os.path.join(WORK_DIR, case_name + "_verify")
    if os.path.exists(verify_dir):
        shutil.rmtree(verify_dir)
    shutil.copytree(snap_src, verify_dir, symlinks=True)

    if patch_content:
        patch_file = os.path.join(verify_dir, "kgcompass.patch")
        with open(patch_file, "w") as f:
            f.write(patch_content)
        r1 = subprocess.run(["patch", "-p1", "--batch", "--fuzz=3", "-i", patch_file],
                            cwd=verify_dir, capture_output=True, text=True, timeout=30)
        if r1.returncode != 0:
            r2 = subprocess.run(["git", "apply", "--verbose", patch_file],
                                cwd=verify_dir, capture_output=True, text=True, timeout=30)
            if r2.returncode != 0:
                return {"status": "patch_apply_failed", "error": r1.stderr[:500]}

    verify_tb = os.path.join(WORK_DIR, case_name + "_tb")
    if os.path.exists(verify_tb):
        shutil.rmtree(verify_tb)
    shutil.copytree(tb_path, verify_tb, symlinks=True)

    run_sh = os.path.join(verify_tb, "run.sh")
    if os.path.isfile(run_sh):
        with open(run_sh, "r") as f:
            content = f.read()
        content = content.replace(f"../../snapshots/{case_name}", verify_dir)
        with open(run_sh, "w") as f:
            f.write(content)

    try:
        result = subprocess.run(["bash", "run.sh"], cwd=verify_tb,
                                capture_output=True, text=True, timeout=120)
        output = result.stdout + "\n" + result.stderr
    except subprocess.TimeoutExpired:
        output = "TIMEOUT"
    except Exception as e:
        output = f"ERROR: {e}"

    pass_count = sum(1 for l in output.split("\n") if re.match(r'^\s*(PASS:|(\[PASS\]))', l.strip()))
    fail_count = sum(1 for l in output.split("\n") if re.match(r'^\s*(FAIL:|(\[FAIL\]))', l.strip()))

    return {
        "status": "completed",
        "pass_count": pass_count,
        "fail_count": fail_count,
        "resolved": pass_count > 0 and fail_count == 0,
    }


def main():
    parser = argparse.ArgumentParser(description="Run KGCompass (LLM-loc + repair) on HDL issues")
    parser.add_argument("--task_id", default=None)
    parser.add_argument("--skip_existing", action="store_true", default=True)
    parser.add_argument("--no_skip", action="store_true")
    parser.add_argument("--model", default=MODEL_NAME)
    args = parser.parse_args()

    _update_model(args.model)

    if args.no_skip:
        args.skip_existing = False

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    os.makedirs(WORK_DIR, exist_ok=True)

    cases = discover_cases()
    print(f"[batch] total_cases={len(cases)} model={MODEL_NAME}")

    summary = {"total": 0, "completed": 0, "resolved": 0, "error": 0, "empty_patch": 0}

    for case_name in cases:
        if args.task_id and args.task_id != case_name:
            continue

        case_output = os.path.join(OUTPUT_DIR, case_name)
        result_file = os.path.join(case_output, "result.json")

        if args.skip_existing and os.path.isfile(result_file):
            print(f"[skip] {case_name}")
            continue

        summary["total"] += 1
        print(f"\n[batch] ==== {case_name} ====")
        os.makedirs(case_output, exist_ok=True)

        try:
            # Read issue
            with open(os.path.join(ISSUES_DIR, case_name), "r") as f:
                issue_text = f.read().strip()

            snap_path = os.path.join(SNAPSHOTS_DIR, case_name)
            work_path = prepare_work_copy(case_name)

            # Step 1: Localize
            print(f"  [localize] ...")
            file_list = get_repo_file_list(snap_path)
            locations = step_localize(issue_text, snap_path, file_list)
            print(f"  [localize] Found {len(locations)} locations: {[l.get('file_path','?') for l in locations[:5]]}")

            # Save locations
            with open(os.path.join(case_output, "locations.json"), "w") as f:
                json.dump(locations, f, indent=2)

            # Step 2: Repair
            print(f"  [repair] ...")
            raw_output = step_repair(issue_text, snap_path, locations)

            # Save raw LLM output
            with open(os.path.join(case_output, "raw_repair_output.txt"), "w") as f:
                f.write(raw_output or "")

            # Step 3: Apply SEARCH/REPLACE to work copy
            applied = apply_search_replace(work_path, raw_output)

            # Extract git diff
            patch_content = extract_git_diff(work_path)
            with open(os.path.join(case_output, "patch.diff"), "w") as f:
                f.write(patch_content or "")

            if not patch_content:
                print(f"  [warn] No patch generated")
                summary["empty_patch"] += 1

            # Step 4: Verify
            print(f"  [verify] Running testbench...")
            verify_result = verify_patch(case_name, patch_content)
            print(f"  [verify] {verify_result}")

            result = {
                "case_name": case_name,
                "status": "completed",
                "num_locations": len(locations),
                "patch_size": len(patch_content) if patch_content else 0,
                "has_diff": bool(patch_content and "diff --git" in patch_content),
                "verify": verify_result,
            }
            summary["completed"] += 1
            if verify_result.get("resolved"):
                summary["resolved"] += 1

        except Exception as e:
            print(f"  [error] {e}")
            traceback.print_exc()
            result = {"case_name": case_name, "status": "error", "error": str(e)}
            summary["error"] += 1

        with open(result_file, "w") as f:
            json.dump(result, f, indent=2)

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

    with open(os.path.join(OUTPUT_DIR, "summary.json"), "w") as f:
        json.dump(summary, f, indent=2)


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Run a testbench once in its fixed/post-patch phase.

The per-case run_once.sh wrappers call this helper with the existing
run_verilator.sh.  It derives a temporary fixed-only script from the existing
two-phase script so the original F2P/P2P runner remains intact.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path


BUG_START_PATTERNS = (
    re.compile(r"^\s*echo\b.*BUGGY"),
    re.compile(r"^\s*prepare_phase\s+buggy\b"),
    re.compile(r"^\s*run_phase\s+buggy\b"),
    re.compile(r"^\s*run_[A-Za-z0-9_]+\s+buggy\b"),
    re.compile(r"^\s*build_and_run\s+buggy\b"),
)

SUMMARY_PATTERNS = (
    re.compile(r'^\s*echo\s+["\']buggy:'),
    re.compile(r'^\s*echo\s+["\'].*buggy phase exit'),
    re.compile(r'^\s*echo\b.*Verdict', re.IGNORECASE),
    re.compile(r"^\s*#\s*-*\s*Verdict\b", re.IGNORECASE),
    re.compile(r"^\s*if\s+\[\[.*buggy_?rc"),
    re.compile(r"^\s*if\s+\[.*buggy_?rc"),
    re.compile(r"^\s*\(\[.*rc_buggy"),
    re.compile(r"^\s*if\b.*(rc_buggy|buggy_rc)"),
    re.compile(r"^\s*if\b.*\$(cb|buggy_count|pre_count)\b"),
)


def line_has_buggy_within(lines: list[str], index: int, window: int = 12) -> bool:
    return any("buggy" in line.lower() for line in lines[index : index + window])


def find_common_source(lines: list[str]) -> int | None:
    for index, line in enumerate(lines):
        if "_rtl_bug_run_common.sh" in line:
            return index
    return None


def find_bug_start(lines: list[str]) -> int | None:
    candidates: list[int] = []
    for index, line in enumerate(lines):
        if any(pattern.search(line) for pattern in BUG_START_PATTERNS):
            candidates.append(index)
        if re.search(r"^\s*set\s+\+e\b", line) and line_has_buggy_within(lines, index):
            candidates.append(index)
    return min(candidates) if candidates else None


def find_fixed_start(lines: list[str], bug_start: int) -> int | None:
    def backtrack_fixed_prep(index: int) -> int:
        start = index
        while start > bug_start + 1:
            previous = lines[start - 1]
            if not previous.strip():
                start -= 1
                continue
            if re.search(r"^\s*prepare_phase\s+fixed\b", previous):
                start -= 1
                continue
            if "$SCRATCH" in previous and (
                "rm -rf" in previous or re.search(r"\bcp\s", previous) or "chmod" in previous
            ):
                start -= 1
                continue
            break
        return start

    for index in range(bug_start + 1, len(lines)):
        if re.search(r"^\s*echo\b.*(FIXED|POST_PATCH)", lines[index]):
            return backtrack_fixed_prep(index)

    for index in range(bug_start + 1, len(lines)):
        line = lines[index]
        if re.search(r"^\s*(prepare_phase|run_phase|build_and_run|run_[A-Za-z0-9_]+)\s+fixed\b", line):
            return backtrack_fixed_prep(index)
        if re.search(r"patch\s+-p1\s+-f\b", line) and "-R" not in line:
            return backtrack_fixed_prep(index)

    for index in range(bug_start + 1, len(lines)):
        if re.search(r"(rc_buggy|buggy_rc)=\$\?", lines[index]):
            return min(index + 1, len(lines))
    return None


def find_fixed_end(lines: list[str], fixed_start: int) -> int:
    for index in range(fixed_start + 1, len(lines)):
        if any(pattern.search(lines[index]) for pattern in SUMMARY_PATTERNS):
            return index
    return len(lines)


def append_once_gate(out: list[str], name_expr: str = "${NAME:-${BASE:-$(basename \"$HERE\")}}") -> None:
    out.extend(
        [
            "",
            'if [ "${rc_fixed+x}" = x ]; then',
            '  rc_once="$rc_fixed"',
            'elif [ "${fixed_rc+x}" = x ]; then',
            '  rc_once="$fixed_rc"',
            'elif [ "${rc+x}" = x ]; then',
            '  rc_once="$rc"',
            "else",
            "  rc_once=0",
            "fi",
            'echo "once:$rc_once"',
            'if [ "$rc_once" = "0" ]; then',
            f'  echo "PASS: {name_expr}"',
            "  exit 0",
            "else",
            f'  echo "FAIL: {name_expr}"',
            "  exit 1",
            "fi",
            "",
        ]
    )


def derive_common_fixed(lines: list[str], source_index: int) -> str:
    out = lines[:source_index]
    out.extend(
        [
            "",
            "# Generated fixed-only body for scripts that normally source _rtl_bug_run_common.sh.",
            'REPO_ROOT="/workspace/phoenix-bench/HDL_agent_eval/benchmark_gemini"',
            'SNAPSHOT="$REPO_ROOT/snapshots/$NAME"',
            'PATCH_FILE="$REPO_ROOT/patches/$NAME.patch"',
            'SCRATCH="$HERE/snapshot_scratch"',
            '. "$HERE/../_testcase_minimum.sh"',
            '. "$HERE/../_repo_native_p2p_smoke.sh"',
            "",
            "trap 'rm -rf \"$SCRATCH\" obj_dir' EXIT",
            "",
            "rm -rf \"$SCRATCH\"",
            "cp -a \"$SNAPSHOT\" \"$SCRATCH\"",
            "chmod -R u+w \"$SCRATCH\"",
            "(cd \"$SCRATCH\" && patch -p1 -f --no-backup-if-mismatch < \"$PATCH_FILE\" >/dev/null 2>&1) || true",
            "",
            "echo RUN_ONCE",
            "set +e",
            "rm -rf obj_dir verilator_fixed_build.log verilator_fixed.log",
            "rm -f coverage.dat verilator_fixed_coverage.dat verilator_fixed_coverage.info",
            "run_repo_native_p2p_smoke fixed",
            "rc_fixed=$?",
            'if [ "$rc_fixed" = "0" ] && declare -F run_patch_target_compile_evidence >/dev/null 2>&1; then',
            "  run_patch_target_compile_evidence fixed",
            "  rc_fixed=$?",
            "fi",
            'if [ "$rc_fixed" = "0" ]; then',
            "  verilator --cc --exe --build --timing --sv --coverage --prefix Vhwe_cov_top \\",
            "    --Wno-fatal --Wno-WIDTH --Wno-UNUSEDSIGNAL --Wno-DECLFILENAME --Wno-PROCASSINIT \\",
            "    --timescale 1ns/1ps \\",
            '    "${SOURCES[@]}" "$HERE/../_coverage_main.cpp" \\',
            '    --top-module "$TOP" \\',
            "    -Mdir obj_dir -o simv_vlt 2>&1 | tee -a verilator_fixed_build.log >/dev/null",
            "  rc_fixed=${PIPESTATUS[0]}",
            "fi",
            'if [ "$rc_fixed" = "0" ]; then',
            "  timeout 20 ./obj_dir/simv_vlt 2>&1 | tee verilator_fixed.log >/dev/null",
            "  rc_fixed=${PIPESTATUS[0]}",
            "fi",
            'if [ "$rc_fixed" = "0" ] && [ -s coverage.dat ]; then',
            "  mv coverage.dat verilator_fixed_coverage.dat",
            "  verilator_coverage --write-info verilator_fixed_coverage.info verilator_fixed_coverage.dat >/dev/null 2>&1 || true",
            "fi",
            'if [ "$rc_fixed" = "0" ]; then',
            "  grep -qE '(^|[^A-Za-z])PASS:' verilator_fixed.log \\",
            "    && ! grep -qE '(^|[^A-Za-z])(FAIL:|\\$fatal|Aborting\\.\\.\\.)' verilator_fixed.log",
            "  rc_fixed=$?",
            "fi",
        ]
    )
    append_once_gate(out)
    return "\n".join(out) + "\n"


def derive_fixed_only(lines: list[str]) -> str | None:
    common_source = find_common_source(lines)
    if common_source is not None:
        return derive_common_fixed(lines, common_source)

    bug_start = find_bug_start(lines)
    if bug_start is None:
        return None

    if re.search(r"\bbuild_and_run\s+fixed\b", lines[bug_start]):
        out = lines[:bug_start]
        out.extend(
            [
                "",
                "# Generated fixed-only body extracted from the original one-line phase runner.",
                'REPO_ROOT="/workspace/phoenix-bench/HDL_agent_eval/benchmark_gemini"',
                "echo RUN_ONCE",
                "set +e",
                "build_and_run fixed",
                "fixed_rc=$?",
            ]
        )
        append_once_gate(out)
        return "\n".join(out) + "\n"

    fixed_start = find_fixed_start(lines, bug_start)
    if fixed_start is None:
        return None

    fixed_end = find_fixed_end(lines, fixed_start)
    out = lines[:bug_start]
    out.extend(
        [
            "",
            "# Generated fixed-only body extracted from the original run_verilator.sh.",
            'REPO_ROOT="/workspace/phoenix-bench/HDL_agent_eval/benchmark_gemini"',
            "echo RUN_ONCE",
            "set +e",
        ]
    )
    out.extend(lines[fixed_start:fixed_end])
    append_once_gate(out)
    return "\n".join(out) + "\n"


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: _run_once_from_run_verilator.py /path/to/run_verilator.sh", file=sys.stderr)
        return 2

    source = Path(sys.argv[1]).absolute()
    if not source.is_file():
        print(f"missing run_verilator.sh: {source}", file=sys.stderr)
        return 2

    lines = source.read_text(errors="replace").splitlines()
    generated = derive_fixed_only(lines)

    if generated is None:
        # Some directories already carry a single-run script; use it unchanged.
        return subprocess.call(["bash", str(source)], cwd=str(source.parent))

    temp = source.parent / ".run_once_expanded.sh"
    # Ensure we use a unique temp file in case of parallel runs
    import tempfile
    with tempfile.NamedTemporaryFile(mode='w', suffix='.sh', dir=str(source.parent), delete=False) as f:
        f.write(generated)
        temp_path = Path(f.name)
    
    temp_path.chmod(0o755)
    try:
        return subprocess.call(["bash", str(temp_path)], cwd=str(source.parent))
    finally:
        try:
            temp_path.unlink()
        except FileNotFoundError:
            pass


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Audit or run Verilator testbenches against patch-scoped snapshot inputs.

The intended contract for these cases is:
  * the target HDL files come from patches/<case>.patch, or from file paths
    mentioned in issues/<case>;
  * the testbench compiles the corresponding files from
    snapshots/<case> via a per-run snapshot_scratch copy;
  * the testbench instantiates a DUT, drives input/timing stimulus, compares
    DUT-observable signals or state against expected behavior, and fails on
    mismatch / passes on match;
  * the buggy/pre-patch phase fails and the fixed/post-patch phase passes.

By default this script is a fast static/log audit.  Pass --run to execute
run_verilator.sh for the selected cases and parse the fresh phase result.
"""

from __future__ import annotations

import argparse
import csv
import os
import re
import subprocess
import time
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parent
TB_DIR = ROOT / "testbench_verilator"
SNAP_DIR = ROOT / "snapshots"
PATCH_DIR = ROOT / "patches"
ISSUE_DIR = ROOT / "issues"

DEFAULT_HDL_EXTS = (".sv", ".v", ".svh", ".vh")
PASS_RE = re.compile(r"(^|[^A-Za-z])(?:\[PASS\]|PASS:|\bPASS(?:ED)?\b)")
FAIL_RE = re.compile(r"(^|[^A-Za-z])(?:\[FAIL\]|FAIL:|\bFAIL\b|%Fatal:|%Error:|Aborting\.\.\.)")
PHASE_RE = re.compile(r"\bbuggy\s*:\s*(-?\d+)\s+fixed\s*:\s*(-?\d+)\b")
ISSUE_PATH_RE = re.compile(r"(?<![\w./-])([A-Za-z0-9_./@+\-]+?\.(?:svh|sv|vh|v))\b")


@dataclass
class PatchInfo:
    files: set[str]
    added: dict[str, set[int]]
    deleted: dict[str, set[int]]
    new_files: set[str]
    removed_files: set[str]


@dataclass
class TbQuality:
    source_count: int
    dut_instances: set[str]
    dut_modules: set[str]
    target_modules: set[str]
    instantiates_target_module: bool
    has_stimulus: bool
    has_signal_compare: bool
    has_pass_fail_paths: bool

    @property
    def semantic_ok(self) -> bool:
        return (
            bool(self.dut_instances)
            and self.has_stimulus
            and self.has_signal_compare
            and self.has_pass_fail_paths
        )


def norm_rel(path: str) -> str:
    path = path.strip().strip("`'\".,;:()[]{}<>")
    path = path.replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return path


def is_hdl(path: str, exts: tuple[str, ...]) -> bool:
    return Path(path).suffix.lower() in exts


def parse_patch(patch_path: Path, exts: tuple[str, ...]) -> PatchInfo:
    files: set[str] = set()
    added: dict[str, set[int]] = {}
    deleted: dict[str, set[int]] = {}
    new_files: set[str] = set()
    removed_files: set[str] = set()
    old_file: str | None = None
    new_file: str | None = None
    old_line: int | None = None
    new_line: int | None = None
    next_new_file = False
    diff_old_file: str | None = None
    diff_new_file: str | None = None

    if not patch_path.exists():
        return PatchInfo(files, added, deleted, new_files, removed_files)

    for raw in patch_path.read_text(errors="replace").splitlines():
        if raw.startswith("diff --git "):
            parts = raw.split()
            diff_old_file = None
            diff_new_file = None
            if len(parts) >= 4:
                diff_old_file = norm_rel(parts[2].removeprefix("a/"))
                diff_new_file = norm_rel(parts[3].removeprefix("b/"))
                if (
                    diff_old_file in new_files
                    and diff_new_file
                    and diff_new_file != diff_old_file
                    and is_hdl(diff_new_file, exts)
                ):
                    files.add(diff_new_file)
                    added.setdefault(diff_new_file, set())
                    new_files.add(diff_new_file)
            old_file = None
            new_file = None
            old_line = None
            new_line = None
            next_new_file = False
            continue
        if raw.startswith("new file mode "):
            next_new_file = True
            if diff_new_file and is_hdl(diff_new_file, exts):
                files.add(diff_new_file)
                added.setdefault(diff_new_file, set())
                new_files.add(diff_new_file)
            continue
        if raw.startswith("rename from "):
            old_file = norm_rel(raw.removeprefix("rename from "))
            if old_file and is_hdl(old_file, exts):
                files.add(old_file)
                removed_files.add(old_file)
            continue
        if raw.startswith("rename to "):
            new_file = norm_rel(raw.removeprefix("rename to "))
            if new_file and is_hdl(new_file, exts):
                files.add(new_file)
                added.setdefault(new_file, set())
                new_files.add(new_file)
            continue
        if raw.startswith("--- "):
            parts = raw.split(maxsplit=1)
            if len(parts) < 2:
                continue
            token = parts[1]
            old_file = None if token == "/dev/null" else norm_rel(token.removeprefix("a/"))
            if old_file and is_hdl(old_file, exts):
                files.add(old_file)
                deleted.setdefault(old_file, set())
            continue
        if raw.startswith("+++ "):
            parts = raw.split(maxsplit=1)
            if len(parts) < 2:
                continue
            token = parts[1]
            new_file = None if token == "/dev/null" else norm_rel(token.removeprefix("b/"))
            if new_file and is_hdl(new_file, exts):
                files.add(new_file)
                added.setdefault(new_file, set())
                if old_file is None or next_new_file:
                    new_files.add(new_file)
                next_new_file = False
            if new_file is None and old_file and is_hdl(old_file, exts):
                removed_files.add(old_file)
            continue

        m = re.match(r"^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@", raw)
        if m:
            old_line = int(m.group(1))
            new_line = int(m.group(2))
            continue

        if old_line is None or new_line is None:
            continue

        if raw.startswith("+") and not raw.startswith("+++"):
            if new_file and is_hdl(new_file, exts):
                added.setdefault(new_file, set()).add(new_line)
            new_line += 1
        elif raw.startswith("-") and not raw.startswith("---"):
            if old_file and is_hdl(old_file, exts):
                deleted.setdefault(old_file, set()).add(old_line)
            old_line += 1
        elif not raw.startswith("\\"):
            old_line += 1
            new_line += 1

    added = {k: v for k, v in added.items() if v}
    deleted = {k: v for k, v in deleted.items() if v}
    return PatchInfo(files, added, deleted, new_files, removed_files)


def issue_hdl_file_mentions(case: str, exts: tuple[str, ...]) -> set[str]:
    issue_path = ISSUE_DIR / case
    if not issue_path.exists() or not issue_path.is_file():
        return set()
    text = issue_path.read_text(errors="replace")
    out = {norm_rel(m.group(1)) for m in ISSUE_PATH_RE.finditer(text)}
    return {p for p in out if is_hdl(p, exts)}


def resolve_issue_hdl_files(case: str, mentions: set[str], patch_files: set[str]) -> set[str]:
    snapshot = SNAP_DIR / case
    resolved: set[str] = set()
    for raw in mentions:
        rel = norm_rel(raw)
        if rel.startswith("/path/"):
            continue
        if rel.startswith("/"):
            rel = Path(rel).name

        if (snapshot / rel).exists():
            resolved.add(rel)
            continue

        patch_matches = [p for p in patch_files if Path(p).name == Path(rel).name]
        if len(patch_matches) == 1:
            resolved.add(patch_matches[0])
            continue

        if snapshot.is_dir():
            matches = [
                str(path.relative_to(snapshot)).replace("\\", "/")
                for path in snapshot.rglob(Path(rel).name)
                if path.is_file()
            ]
            if len(matches) == 1:
                resolved.add(matches[0])
                continue
            if matches:
                matches.sort(key=lambda p: (p.count("/"), len(p), p))
                shortest_depth = matches[0].count("/")
                shortest = [p for p in matches if p.count("/") == shortest_depth]
                if len(shortest) == 1:
                    resolved.add(shortest[0])
                    continue

        if not patch_files:
            resolved.add(raw)
    return resolved


def rel_for_source(source: str, targets: set[str]) -> str | None:
    normalized = source.replace("\\", "/")
    for rel in targets:
        if normalized == rel or normalized.endswith("/" + rel):
            return rel
    return None


def read_text(path: Path) -> str:
    try:
        size = path.stat().st_size
        if size <= 8 * 1024 * 1024:
            return path.read_text(errors="replace")
        with path.open("rb") as f:
            head = f.read(2 * 1024 * 1024)
            f.seek(max(0, size - 2 * 1024 * 1024))
            tail = f.read(2 * 1024 * 1024)
        marker = f"\n\n... <truncated {size} byte file> ...\n\n".encode()
        return (head + marker + tail).decode("utf-8", errors="replace")
    except OSError:
        return ""


def run_script_context(case_dir: Path, run_script: Path) -> str:
    """Return run_verilator.sh plus local helper files it sources.

    Many compact run scripts put only SOURCES/TOP in the case directory and
    delegate snapshot copy plus patch/reverse-patch phases to shared helpers.
    For audit purposes those helpers are part of the run contract.
    """
    text = read_text(run_script)
    if not text:
        return ""

    chunks = [text]
    candidates = [
        TB_DIR / "_rtl_bug_run_common.sh",
        TB_DIR / "_testcase_minimum.sh",
    ]
    for helper in candidates:
        if helper.name in text:
            chunks.append(read_text(helper))
    return "\n".join(chunks)


def strip_comments(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return "\n".join(line.split("//", 1)[0] for line in text.splitlines())


def local_tb_sources(case_dir: Path, exts: tuple[str, ...]) -> list[Path]:
    if not case_dir.is_dir():
        return []
    out: list[Path] = []
    ignored_parts = {"snapshot_scratch", "obj_dir", "__pycache__"}
    for root, dirs, files in os.walk(case_dir):
        dirs[:] = [d for d in dirs if d not in ignored_parts and not d.startswith("obj_dir")]
        root_path = Path(root)
        for name in files:
            path = root_path / name
            if path.suffix.lower() in exts:
                out.append(path)
    return sorted(out)


def parse_declared_modules(text: str) -> set[str]:
    clean = strip_comments(text)
    return {
        m.group(2)
        for m in re.finditer(
            r"(?m)^\s*(module|interface|program|primitive)\s+([A-Za-z_$][\w$]*)\b",
            clean,
        )
    }


def target_module_names(case: str, targets: set[str], patch_file: Path) -> set[str]:
    modules: set[str] = set()
    snapshot = SNAP_DIR / case
    for rel in targets:
        path = snapshot / rel
        if path.exists():
            modules.update(parse_declared_modules(read_text(path)))

    # If a patch adds a new module that is not present in a pre-patch
    # snapshot, recover the name from added hunk lines.
    if patch_file.exists():
        added_text = "\n".join(
            line[1:] for line in patch_file.read_text(errors="replace").splitlines()
            if line.startswith("+") and not line.startswith("+++")
        )
        modules.update(parse_declared_modules(added_text))
    return modules


def dut_instances_from_text(text: str) -> tuple[set[str], set[str]]:
    clean = strip_comments(text)
    instances: set[str] = set()
    modules: set[str] = set()

    direct_re = re.compile(
        r"(?m)^\s*(`?[A-Za-z_$][\w$]*)\s*(?:#\s*\([^;]*?\)\s*)?"
        r"\s+([A-Za-z_$][\w$]*)\s*\(",
        re.S,
    )
    for match in direct_re.finditer(clean):
        module = match.group(1).lstrip("`")
        inst = match.group(2)
        if module in {"module", "function", "task", "if", "for", "while", "case"}:
            continue
        if "dut" not in inst.lower() and "uut" not in inst.lower():
            continue
        modules.add(module)
        instances.add(inst)

    # Parameterized instances can appear as:
    #   some_module #(... lots of lines ... ) dut (
    # The direct regex normally catches these, but this fallback keeps the
    # audit robust for heavily formatted generated testbenches.
    for match in re.finditer(
        r"\)\s+([A-Za-z_$][\w$]*)\s*\(",
        clean,
    ):
        inst = match.group(1)
        if "dut" in inst.lower() or "uut" in inst.lower():
            instances.add(inst)

    return instances, modules


def has_stimulus(text: str) -> bool:
    clean = strip_comments(text)
    has_time_or_sequence = bool(
        re.search(r"(#\s*\d+|@\s*\(|\bposedge\b|\bnegedge\b|\brepeat\s*\(|\bfor\s*\(|\bforever\b)", clean)
    )
    assignment_re = re.compile(
        r"(?m)^\s*(?!assign\b|parameter\b|localparam\b|wire\b|logic\b|reg\b)"
        r"(?:[A-Za-z_$][\w$]*(?:\[[^\]]+\])?|\{[^}]+\}|[A-Za-z_$][\w$]*\.[A-Za-z_$][\w$]*)\s*(?:<=|=)\s*[^=]"
    )
    assignments = len(assignment_re.findall(clean))
    has_clock_toggle = bool(re.search(r"\b[A-Za-z_$][\w$]*(?:clk|clock)[A-Za-z_$\w]*\s*=\s*~", clean, re.I))
    return assignments >= 2 and (has_time_or_sequence or has_clock_toggle)


def has_signal_compare(text: str) -> bool:
    clean = strip_comments(text)
    has_fail_action = bool(re.search(r"(\$fatal|\$error|\bFAIL:|\[FAIL\])", clean))
    if not has_fail_action:
        return False

    # This intentionally accepts checks against internal DUT state, mirrored
    # scoreboards, sideband flags, counters, or output ports.  The requirement
    # is a real signal/result comparison, not specifically an output-port check.
    comparison = bool(
        re.search(r"\bif\s*\([^;\n]*(?:!==|===|!=|==|<=|>=|<|>)", clean)
        or re.search(r"\bassert\s*(?:final\s*)?\(", clean)
    )
    check_task = bool(re.search(r"\bcheck(?:_[A-Za-z0-9_$]+)?\s*\(", clean))
    dut_ref = bool(re.search(r"\b(?:dut|uut)[A-Za-z0-9_$]*(?:\.|\b)", clean, re.I))
    return (comparison or check_task) and dut_ref


def pass_fail_paths(text: str) -> bool:
    clean = strip_comments(text)
    has_pass = bool(re.search(r"(\bPASS:|\[PASS\]|\bPASSED\b)", clean))
    has_fail = bool(re.search(r"(\bFAIL:|\[FAIL\]|\$fatal|\$error|\bassert\s*\()", clean))
    return has_pass and has_fail


def testbench_quality(case: str, targets: set[str], patch_file: Path, exts: tuple[str, ...]) -> TbQuality:
    case_dir = TB_DIR / case
    sources = local_tb_sources(case_dir, exts)
    texts = [read_text(path) for path in sources]
    joined = "\n".join(texts)
    dut_instances: set[str] = set()
    dut_modules: set[str] = set()
    for text in texts:
        instances, modules = dut_instances_from_text(text)
        dut_instances.update(instances)
        dut_modules.update(modules)

    target_modules = target_module_names(case, targets, patch_file)
    return TbQuality(
        source_count=len(sources),
        dut_instances=dut_instances,
        dut_modules=dut_modules,
        target_modules=target_modules,
        instantiates_target_module=bool(dut_modules & target_modules),
        has_stimulus=has_stimulus(joined),
        has_signal_compare=has_signal_compare(joined),
        has_pass_fail_paths=pass_fail_paths(joined),
    )


def script_uses_all_scratch_sources(text: str) -> bool:
    has_find = "find" in text and ("$SCRATCH" in text or "snapshot_scratch" in text)
    has_hdl_glob = any(tok in text for tok in ("*.sv", "*.v", "-name '*.sv'", '-name "*.sv"', "-name '*.v'", '-name "*.v"'))
    return has_find and has_hdl_glob


def mentioned_targets(text: str, targets: set[str]) -> set[str]:
    if script_uses_all_scratch_sources(text):
        return set(targets)
    out: set[str] = set()
    for rel in targets:
        base = Path(rel).name
        if rel in text or base in text:
            out.add(rel)
    return out


def compiler_source_evidence(text: str, target_refs: set[str]) -> bool:
    """Accept lint/compiler-source tests only when a real tool is invoked.

    Some issues are compiler/linter/UVM-class regressions rather than DUT
    behavior.  Those are valid without a traditional DUT instance, but only if
    the runner invokes a real parser/compiler/linter on the snapshot/patch
    sources.  Text-only greps, and Verilator preprocessing-only (-E), do not
    satisfy this path.
    """
    if not target_refs and not script_uses_all_scratch_sources(text):
        return False

    clean = strip_comments(text)
    clean = re.sub(r"\\\s*\n\s*", " ", clean)
    lines = [line.strip() for line in clean.splitlines()]

    compile_cmd = re.compile(
        r"("
        r"\bverilator\b(?=.*(?:--lint-only|--cc|--binary|--xml-only))|"
        r"\biverilog\b|"
        r"\byosys\b|"
        r"\bslang\b|"
        r"\bsvlint\b|"
        r"\bpyslint\.py\b"
        r")"
    )
    target_var = re.compile(
        r"(\$\{?target\}?|\$\{?src\}?|\$\{?source\}?|\$\{?SOURCES\[@\]\}?|"
        r"\bSOURCES\b|\bPATCH_TARGETS\b|\btarget_sources\b|"
        r"\bfind\b.*(?:\$SCRATCH|snapshot_scratch))"
    )

    for line in lines:
        if not compile_cmd.search(line):
            continue
        if script_uses_all_scratch_sources(line):
            return True
        if "LINT_WRAPPER" in line and any(ref.endswith((".svh", ".vh")) and ref in clean for ref in target_refs):
            return True
        if target_var.search(line):
            return True
        for rel in target_refs:
            base = Path(rel).name
            if rel in line or base in line:
                return True
    if (
        re.search(r"VERILATOR_FLAGS=.*--lint-only", clean, re.S)
        and re.search(r"\bcmd=\(\s*verilator\b", clean)
        and re.search(r"\bcmd\+=\([^)]*\$SCRATCH/\$target", clean)
        and re.search(r'"\$\{cmd\[@\]\}"', clean)
    ):
        return True
    return False


def overwrites_target_sources(text: str, targets: set[str]) -> bool:
    """Detect local replacement models copied/written over patch target files."""
    if not targets:
        return False
    clean = strip_comments(text)
    suspicious_model_writer = bool(re.search(r"\bwrite_(?:target_)?model\b|\bfixed_src\b", clean))
    for rel in targets:
        rel_re = re.escape(rel)
        base_re = re.escape(Path(rel).name)
        if re.search(r">\s*\"?\$SCRATCH/" + rel_re + r"\"?", clean):
            return True
        if re.search(r"\bcp\b[^\n]*\bfixed_src\b[^\n]*\$SCRATCH/" + rel_re, clean):
            return True
        if suspicious_model_writer and re.search(r"\$SCRATCH/[^\n\"']*" + base_re, clean):
            return True
    return False


def parse_lcov(case_dir: Path, targets: set[str], added: dict[str, set[int]]) -> tuple[set[str], int, int]:
    info_path = case_dir / "verilator_fixed_coverage.info"
    if not info_path.exists():
        info_path = case_dir / "coverage.info"
    if not info_path.exists():
        return set(), 0, 0

    files_seen: set[str] = set()
    current: str | None = None
    added_total = 0
    added_hit = 0
    seen_lines: set[tuple[str, int]] = set()

    for raw in info_path.read_text(errors="replace").splitlines():
        if raw.startswith("SF:"):
            current = rel_for_source(raw[3:], targets)
            if current:
                files_seen.add(current)
            continue
        if current is None or not raw.startswith("DA:"):
            continue
        try:
            line_s, count_s = raw[3:].split(",", 1)[:2]
            line_no = int(line_s)
            count = int(count_s.split(",", 1)[0])
        except ValueError:
            continue
        key = (current, line_no)
        if line_no in added.get(current, set()) and key not in seen_lines:
            seen_lines.add(key)
            added_total += 1
            if count > 0:
                added_hit += 1

    return files_seen, added_hit, added_total


def log_phase_result(case_dir: Path) -> tuple[str, str, bool, bool]:
    buggy_phase = read_text(case_dir / "verilator_buggy_phase.log")
    fixed_phase = read_text(case_dir / "verilator_fixed_phase.log")
    if buggy_phase or fixed_phase:
        buggy_fail = bool(FAIL_RE.search(buggy_phase))
        fixed_pass = bool(PASS_RE.search(fixed_phase)) and not bool(FAIL_RE.search(fixed_phase))
        return (
            "fail" if buggy_fail else "unknown",
            "pass" if fixed_pass else "unknown",
            buggy_fail,
            fixed_pass,
        )

    buggy_log = read_text(case_dir / "verilator_buggy.log")
    buggy_build = read_text(case_dir / "verilator_buggy_build.log")
    fixed_log = read_text(case_dir / "verilator_fixed.log")
    fixed_build = read_text(case_dir / "verilator_fixed_build.log")

    buggy_text = "\n".join([buggy_log, buggy_build])
    fixed_text = "\n".join([fixed_log, fixed_build])
    buggy_fail = bool(FAIL_RE.search(buggy_text))
    fixed_pass = bool(PASS_RE.search(fixed_text)) and not bool(FAIL_RE.search(fixed_text))
    return (
        "fail" if buggy_fail else "unknown",
        "pass" if fixed_pass else "unknown",
        buggy_fail,
        fixed_pass,
    )


def dryrun_patch_state(snapshot: Path, patch_file: Path) -> str:
    if not snapshot.is_dir() or not patch_file.exists():
        return "missing"

    def run_patch(reverse: bool) -> int:
        cmd = ["patch", "-p1", "--dry-run", "-f", "--no-backup-if-mismatch"]
        if reverse:
            cmd.append("-R")
        cmd.extend(["-i", str(patch_file)])
        try:
            proc = subprocess.run(
                cmd,
                cwd=str(snapshot),
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=30,
            )
            return proc.returncode
        except (OSError, subprocess.SubprocessError):
            return 99

    forward_ok = run_patch(False) == 0
    reverse_ok = run_patch(True) == 0
    if forward_ok and reverse_ok:
        return "both"
    if forward_ok:
        return "pre_patch"
    if reverse_ok:
        return "post_patch"
    return "patch_mismatch"


def run_case(case_dir: Path, timeout: int) -> tuple[int | None, int | None, int, str]:
    script = case_dir / "run_verilator.sh"
    if not script.exists():
        return None, None, 127, "run_verilator.sh missing"
    try:
        proc = subprocess.run(
            ["bash", "run_verilator.sh"],
            cwd=str(case_dir),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
        out = proc.stdout.decode("utf-8", errors="replace")
    except subprocess.TimeoutExpired as exc:
        out = (exc.stdout or b"").decode("utf-8", errors="replace")
        return None, None, 124, out[-4000:]

    buggy_rc: int | None = None
    fixed_rc: int | None = None
    for match in PHASE_RE.finditer(out):
        buggy_rc = int(match.group(1))
        fixed_rc = int(match.group(2))
    if buggy_rc is not None:
        phase_log = case_dir / "verilator_buggy_phase.log"
        phase_log.write_text(
            ("FAIL" if buggy_rc != 0 else "PASS")
            + f": buggy phase exited rc={buggy_rc}\n",
            encoding="utf-8",
        )
    if fixed_rc is not None:
        phase_log = case_dir / "verilator_fixed_phase.log"
        phase_log.write_text(
            ("PASS" if fixed_rc == 0 else "FAIL")
            + f": fixed phase exited rc={fixed_rc}\n",
            encoding="utf-8",
        )
    return buggy_rc, fixed_rc, proc.returncode, out[-4000:]


def classify(
    targets: set[str],
    missing: set[str],
    uses_snapshot: bool,
    uses_patch: bool,
    overwrites_targets: bool,
    target_refs: set[str],
    covered_files: set[str],
    missing_evidence: set[str],
    tb_quality: TbQuality,
    compiler_source_ok: bool,
    f2p_ok: bool | None,
) -> str:
    if not targets:
        return "NO_HDL_TARGETS"
    if missing:
        missing_allowed_by_f2p_run = (
            f2p_ok is True
            and uses_snapshot
            and uses_patch
            and not missing_evidence
            and (target_refs or covered_files)
            and (tb_quality.semantic_ok or compiler_source_ok)
        )
        if not missing_allowed_by_f2p_run:
            return "SNAPSHOT_TARGET_MISSING"
    if not tb_quality.dut_instances and not compiler_source_ok:
        return "NO_DUT_TESTBENCH"
    if not compiler_source_ok and not tb_quality.has_stimulus:
        return "NO_DUT_STIMULUS"
    if not compiler_source_ok and not tb_quality.has_signal_compare:
        return "NO_SIGNAL_COMPARE"
    if not compiler_source_ok and not tb_quality.has_pass_fail_paths:
        return "NO_PASS_FAIL_PATHS"
    if not uses_snapshot or not uses_patch:
        return "NOT_SNAPSHOT_PATCH_DRIVEN"
    if overwrites_targets:
        return "NOT_SNAPSHOT_PATCH_DRIVEN"
    if not target_refs and not covered_files:
        return "NO_TARGET_FILE_EVIDENCE"
    if (
        not compiler_source_ok
        and tb_quality.dut_instances
        and tb_quality.target_modules
        and not tb_quality.instantiates_target_module
        and not covered_files
    ):
        return "NO_TARGET_FILE_EVIDENCE"
    if missing_evidence:
        return "PARTIAL_TARGET_FILE_EVIDENCE"
    if f2p_ok is True:
        return "PATCH_SCOPED_F2P_OK"
    if f2p_ok is False:
        return "PATCH_SCOPED_F2P_FAIL"
    return "PATCH_SCOPED_NO_F2P_RUN"


def case_names(args: argparse.Namespace) -> list[str]:
    if args.cases:
        return args.cases

    if args.from_csv:
        with Path(args.from_csv).open(newline="") as f:
            reader = csv.DictReader(f)
            field = "case" if "case" in (reader.fieldnames or []) else "instance"
            return [row[field] for row in reader if row.get(field)]

    base = PATCH_DIR if args.all_patches else TB_DIR
    names = sorted(p.stem if p.suffix == ".patch" else p.name for p in base.iterdir() if p.is_dir() or p.suffix == ".patch")
    if args.limit:
        names = names[: args.limit]
    return names


def audit_case(case: str, args: argparse.Namespace, exts: tuple[str, ...]) -> dict[str, str | int]:
    case_dir = TB_DIR / case
    patch_file = PATCH_DIR / f"{case}.patch"
    snapshot = SNAP_DIR / case
    run_script = case_dir / "run_verilator.sh"
    patch = parse_patch(patch_file, exts)
    issue_mentions = issue_hdl_file_mentions(case, exts)
    issue_files = resolve_issue_hdl_files(case, issue_mentions, patch.files)
    targets = set(patch.files) | issue_files
    tb_quality = testbench_quality(case, targets, patch_file, exts)

    script_text = read_text(run_script)
    context_text = run_script_context(case_dir, run_script)
    uses_snapshot = any(tok in context_text for tok in ("SNAPSHOT", "snapshots/", "snapshot_scratch"))
    uses_patch = any(tok in context_text for tok in ("PATCH_FILE", "patches/", "patch -p"))
    uses_scratch = "snapshot_scratch" in context_text or "$SCRATCH" in context_text
    local_phase_files = bool(re.search(r"(^|[^A-Za-z0-9_])(buggy|fixed)[A-Za-z0-9_./-]*\.(?:sv|v)\b", script_text))

    target_refs = mentioned_targets(script_text, targets)
    overwrites_targets = overwrites_target_sources(script_text, targets)
    compiler_source_candidate = compiler_source_evidence(context_text, target_refs)
    patch_creates_in_some_phase = patch.new_files | patch.removed_files
    required_targets = (set(targets) - set(patch.removed_files)) | set(issue_files)
    missing = {
        rel
        for rel in targets
        if not (snapshot / rel).exists() and rel not in patch_creates_in_some_phase
    }
    covered_files, added_hit, added_total = parse_lcov(case_dir, targets, patch.added)
    evidenced_targets = target_refs | covered_files
    missing_evidence = required_targets - evidenced_targets

    run_buggy_rc: int | None = None
    run_fixed_rc: int | None = None
    run_exit: int | None = None
    run_tail = ""
    run_f2p_ok: bool | None = None
    if args.run:
        run_buggy_rc, run_fixed_rc, run_exit, run_tail = run_case(case_dir, args.timeout)
        if run_buggy_rc is not None and run_fixed_rc is not None:
            run_f2p_ok = run_buggy_rc != 0 and run_fixed_rc == 0
        else:
            run_f2p_ok = run_exit == 0

    log_buggy, log_fixed, log_buggy_fail, log_fixed_pass = log_phase_result(case_dir)
    compiler_source_ok = compiler_source_candidate and log_buggy_fail
    f2p_ok = run_f2p_ok
    if f2p_ok is None and log_buggy_fail and log_fixed_pass:
        f2p_ok = None if args.require_run_for_f2p else True

    verdict = classify(
        targets=targets,
        missing=missing,
        uses_snapshot=uses_snapshot and uses_scratch,
        uses_patch=uses_patch,
        overwrites_targets=overwrites_targets,
        target_refs=target_refs,
        covered_files=covered_files,
        missing_evidence=missing_evidence,
        tb_quality=tb_quality,
        compiler_source_ok=compiler_source_ok,
        f2p_ok=f2p_ok,
    )

    notes: list[str] = []
    if not patch_file.exists():
        notes.append("missing patch")
    if not snapshot.is_dir():
        notes.append("missing snapshot")
    if not run_script.exists():
        notes.append("missing run script")
    if local_phase_files:
        notes.append("script has local buggy/fixed HDL names")
    if tb_quality.dut_instances and not tb_quality.instantiates_target_module and tb_quality.target_modules:
        notes.append("DUT module name is not one of the patch target module declarations")
    if args.run and run_tail and not run_f2p_ok:
        notes.append("run tail: " + re.sub(r"\s+", " ", run_tail.strip())[:500])

    return {
        "case": case,
        "verdict": verdict,
        "patch_hdl_files": len(patch.files),
        "patch_new_hdl_files": len(patch.new_files),
        "patch_removed_hdl_files": len(patch.removed_files),
        "issue_hdl_files": len(issue_files),
        "issue_hdl_mentions": len(issue_mentions),
        "target_hdl_files": len(targets),
        "required_target_files": len(required_targets),
        "snapshot_missing_files": len(missing),
        "run_uses_snapshot_scratch": int(uses_snapshot and uses_scratch),
        "run_uses_patch_file": int(uses_patch),
        "run_mentions_target_files": len(target_refs),
        "run_overwrites_target_files": int(overwrites_targets),
        "fixed_coverage_target_files": len(covered_files),
        "evidenced_target_files": len(evidenced_targets),
        "missing_target_evidence_files": len(missing_evidence),
        "fixed_coverage_added_hit": added_hit,
        "fixed_coverage_added_total": added_total,
        "tb_source_files": tb_quality.source_count,
        "dut_instances": ";".join(sorted(tb_quality.dut_instances)),
        "dut_modules": ";".join(sorted(tb_quality.dut_modules)),
        "target_modules": ";".join(sorted(tb_quality.target_modules)),
        "instantiates_target_module": int(tb_quality.instantiates_target_module),
        "has_dut_stimulus": int(tb_quality.has_stimulus),
        "has_signal_compare": int(tb_quality.has_signal_compare),
        "has_pass_fail_paths": int(tb_quality.has_pass_fail_paths),
        "semantic_tb_ok": int(tb_quality.semantic_ok),
        "compiler_source_evidence": int(compiler_source_ok),
        "patch_dryrun_state": dryrun_patch_state(snapshot, patch_file) if args.patch_dryrun else "not_checked",
        "run_buggy_rc": "" if run_buggy_rc is None else run_buggy_rc,
        "run_fixed_rc": "" if run_fixed_rc is None else run_fixed_rc,
        "run_exit": "" if run_exit is None else run_exit,
        "log_buggy": log_buggy,
        "log_fixed": log_fixed,
        "target_files": ";".join(sorted(targets)),
        "required_target_files_list": ";".join(sorted(required_targets)),
        "missing_files": ";".join(sorted(missing)),
        "evidenced_files": ";".join(sorted(evidenced_targets)),
        "missing_evidence_files": ";".join(sorted(missing_evidence)),
        "covered_files": ";".join(sorted(covered_files)),
        "notes": "; ".join(notes),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("cases", nargs="*", help="case names; defaults to testbench_verilator dirs")
    parser.add_argument("--all-patches", action="store_true", help="audit every patches/*.patch instead of only testbench dirs")
    parser.add_argument("--from-csv", help="read case/instance names from a CSV")
    parser.add_argument("--out", default=str(ROOT / "patch_snapshot_f2p_audit.csv"))
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--run", action="store_true", help="execute run_verilator.sh for each selected case")
    parser.add_argument("--timeout", type=int, default=1200)
    parser.add_argument("--require-run-for-f2p", action="store_true", help="do not promote existing logs to F2P_OK")
    parser.add_argument("--patch-dryrun", action="store_true", help="check whether the patch applies/reverses against the snapshot")
    parser.add_argument("--ext", action="append", help="HDL extension to include; may be repeated")
    args = parser.parse_args()

    exts = tuple(e if e.startswith(".") else f".{e}" for e in (args.ext or DEFAULT_HDL_EXTS))
    names = case_names(args)
    rows: list[dict[str, str | int]] = []
    start = time.time()

    for idx, case in enumerate(names, 1):
        row = audit_case(case, args, exts)
        rows.append(row)
        print(f"[{idx}/{len(names)}] {case}: {row['verdict']}", flush=True)

    out_path = Path(args.out)
    if rows:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        with out_path.open("w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            writer.writeheader()
            writer.writerows(rows)

    counts: dict[str, int] = {}
    for row in rows:
        counts[str(row["verdict"])] = counts.get(str(row["verdict"]), 0) + 1

    print("\n=== SUMMARY ===")
    for verdict in sorted(counts):
        print(f"{verdict:28s} {counts[verdict]}")
    print(f"cases: {len(rows)}")
    print(f"elapsed_s: {time.time() - start:.1f}")
    print(f"csv: {out_path}")


if __name__ == "__main__":
    main()

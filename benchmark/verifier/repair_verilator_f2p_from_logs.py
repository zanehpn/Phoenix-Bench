#!/usr/bin/env python3
"""Recover case-level Verilator F2P evidence from existing logs.

The strict case-level F2P contract is:
  buggy side has fail evidence AND fixed side has pass evidence.

This script does not invent evidence. It recovers missing sides only when the
existing logs contain a defensible global signal:
  - fixed global pass: all tests passed / 0 failed / no fatal fail markers
  - buggy global fail: build/runtime fatal/stop/error that prevents case output

Outputs:
  - verilator_f2p_case_repaired.csv: case-level recovered/evaluated rows
  - verilator_f2p_case_missing_before_repair.csv: one-sided rows before recovery
  - verilator_f2p_case_needs_rerun.csv: rows still missing required evidence
  - verilator_f2p_case_repair_summary.csv: count by status/reason
"""

from __future__ import annotations

import argparse
import csv
import re
from collections import Counter
from dataclasses import dataclass
from pathlib import Path


BASE_DIR = Path(__file__).resolve().parent
DEFAULT_ROOT = BASE_DIR / "testbench_verilator"


PASS_LINE_RE = re.compile(
    r"^\s*(?:(?:\[(PASS)\])|(PASS))\s*(?:\[(?P<bracket>[^\]]+)\])?\s*:?\s*(?P<body>.*)$",
    re.IGNORECASE,
)
FAIL_LINE_RE = re.compile(
    r"^\s*(?:(?:\[(FAIL)\])|(FAIL))\s*(?:\[(?P<bracket>[^\]]+)\])?\s*:?\s*(?P<body>.*)$",
    re.IGNORECASE,
)

CASE_ID_PATTERNS = [
    re.compile(r"^(?P<id>T\d+(?:\.[A-Za-z0-9_]+)*)\b\s*:?", re.IGNORECASE),
    re.compile(r"^(?P<id>TEST\s*\d+(?:\.[A-Za-z0-9_]+)*)\b\s*:?", re.IGNORECASE),
    re.compile(r"^(?P<id>CASE\s*\d+(?:\.[A-Za-z0-9_]+)*)\b\s*:?", re.IGNORECASE),
]

AGGREGATE_RE = re.compile(
    r"\b("
    r"all\b.*\btests?\s+passed|"
    r"all\s+checks\s+passed|"
    r"test\s+pass(?:ed)?|"
    r"test\s+summary|"
    r"results?:|"
    r"\d+\s+tests?\s+passed|"
    r"\d+\s+passed,\s*0\s+failed|"
    r"failed:\s*0|"
    r"passed:\s*\d+"
    r")\b",
    re.IGNORECASE,
)
GLOBAL_PASS_RE = re.compile(
    r"\b("
    r"all\b.*\btests?\s+passed|"
    r"all\s+checks\s+passed|"
    r"test\s+pass(?:ed)?|"
    r"\d+\s+tests?\s+passed|"
    r"\d+\s+passed,\s*0\s+failed|"
    r"failed:\s*0|"
    r"0\s+failed"
    r")\b",
    re.IGNORECASE,
)
GLOBAL_FAIL_RE = re.compile(
    r"("
    r"%Fatal:|"
    r"Verilog\s+\$stop|"
    r"\bAborting\b|"
    r"\bFAIL:\s*Verilator build failed|"
    r"\bFAIL\b|"
    r"%Error:|"
    r"Exiting due to \d+ (?:error|warning)|"
    r"make(?:\[\d+\])?: \*\*\*|"
    r"undefined reference|"
    r"cannot find|"
    r"No such file or directory|"
    r"Permission denied"
    r")",
    re.IGNORECASE,
)
FATAL_RE = re.compile(r"(%Fatal:|Verilog\s+\$stop|\bAborting\b)", re.IGNORECASE)


@dataclass(frozen=True)
class Evidence:
    case_id: str
    line: str
    source: str
    explicit_id: bool


def read_text(path: Path) -> str:
    if not path.exists():
        return ""
    return path.read_text(errors="replace")


def clean_body(body: str) -> str:
    body = re.sub(r"\s+", " ", body.strip())
    return body


def body_to_case_id(body: str, bracket: str | None) -> tuple[str, bool]:
    if bracket and bracket.strip():
        b = bracket.strip()
        return re.sub(r"\s+", "", b).upper(), True

    body = clean_body(body)
    for pat in CASE_ID_PATTERNS:
        m = pat.match(body)
        if m:
            return re.sub(r"\s+", "", m.group("id")).upper(), True

    normalized = body.lower()
    normalized = re.sub(r"\bgot\s*=\s*[^,\s]+", "got=<v>", normalized)
    normalized = re.sub(r"\bexpected\s*=\s*[^,\s]+", "expected=<v>", normalized)
    normalized = re.sub(r"\b0x[0-9a-fA-F_]+", "0x<v>", normalized)
    normalized = re.sub(r"\b\d+'[bdh][0-9a-fA-F_xzXZ]+", "<bits>", normalized)
    normalized = re.sub(r"\b\d+\b", "<n>", normalized)
    normalized = re.sub(r"[^a-z0-9_<>.]+", " ", normalized).strip()
    return normalized[:120] or "<unnamed>", False


def parse_cases(text: str, source: str, kind: str) -> list[Evidence]:
    regex = PASS_LINE_RE if kind == "pass" else FAIL_LINE_RE
    out: list[Evidence] = []
    for line in text.splitlines():
        m = regex.match(line)
        if not m:
            continue
        body = clean_body(m.group("body") or "")
        if kind == "pass" and AGGREGATE_RE.search(body):
            continue
        if kind == "fail" and re.search(r"\b0\s+failed\b|failed:\s*0", body, re.IGNORECASE):
            continue
        case_id, explicit = body_to_case_id(body, m.group("bracket"))
        out.append(Evidence(case_id=case_id, line=line.strip(), source=source, explicit_id=explicit))
    return out


def first_match_line(text: str, regex: re.Pattern[str]) -> str:
    for line in text.splitlines():
        if regex.search(line):
            return line.strip()
    return ""


def fixed_global_pass(fixed_log: str) -> tuple[bool, str]:
    if FATAL_RE.search(fixed_log):
        return False, ""
    if re.search(r"^\s*(?:\[FAIL\]|FAIL)\b", fixed_log, re.IGNORECASE | re.MULTILINE):
        return False, ""
    line = first_match_line(fixed_log, GLOBAL_PASS_RE)
    if line:
        return True, line
    pass_cases = parse_cases(fixed_log, "verilator_fixed.log", "pass")
    if pass_cases:
        return True, f"{len(pass_cases)} explicit PASS case(s), no fail/fatal marker"
    return False, ""


def buggy_global_fail(buggy_log: str, buggy_build_log: str) -> tuple[bool, str, str]:
    line = first_match_line(buggy_log, FATAL_RE)
    if line:
        return True, "buggy_runtime_fatal", line
    line = first_match_line(buggy_log, GLOBAL_FAIL_RE)
    if line:
        return True, "buggy_runtime_fail", line
    line = first_match_line(buggy_build_log, GLOBAL_FAIL_RE)
    if line:
        return True, "buggy_build_fail", line
    return False, "", ""


def evidence_by_id(items: list[Evidence]) -> dict[str, Evidence]:
    out: dict[str, Evidence] = {}
    for item in items:
        out.setdefault(item.case_id, item)
    return out


def row(
    instance: str,
    case_id: str,
    status: str,
    reason: str,
    buggy_kind: str,
    fixed_kind: str,
    buggy_evidence: str,
    fixed_evidence: str,
) -> dict[str, str]:
    return {
        "instance": instance,
        "case_id": case_id,
        "status": status,
        "reason": reason,
        "buggy_evidence_kind": buggy_kind,
        "fixed_evidence_kind": fixed_kind,
        "buggy_evidence": buggy_evidence,
        "fixed_evidence": fixed_evidence,
    }


def missing_row(
    instance: str,
    case_id: str,
    missing_side: str,
    observed_evidence_kind: str,
    observed_evidence: str,
    recovery_status: str,
    recovery_reason: str,
    recovery_evidence_kind: str,
    recovery_evidence: str,
) -> dict[str, str]:
    return {
        "instance": instance,
        "case_id": case_id,
        "missing_side": missing_side,
        "observed_evidence_kind": observed_evidence_kind,
        "observed_evidence": observed_evidence,
        "recovery_status": recovery_status,
        "recovery_reason": recovery_reason,
        "recovery_evidence_kind": recovery_evidence_kind,
        "recovery_evidence": recovery_evidence,
    }


def analyze_instance(tb_dir: Path) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    name = tb_dir.name
    fixed_log = read_text(tb_dir / "verilator_fixed.log")
    buggy_log = read_text(tb_dir / "verilator_buggy.log")
    buggy_build_log = read_text(tb_dir / "verilator_buggy_build.log")

    fixed_passes = parse_cases(fixed_log, "verilator_fixed.log", "pass")
    buggy_fails = parse_cases(buggy_log, "verilator_buggy.log", "fail")
    fixed_by_id = evidence_by_id(fixed_passes)
    buggy_by_id = evidence_by_id(buggy_fails)

    has_fixed_global_pass, fixed_global_line = fixed_global_pass(fixed_log)
    has_buggy_global_fail, buggy_global_kind, buggy_global_line = buggy_global_fail(
        buggy_log, buggy_build_log
    )

    rows: list[dict[str, str]] = []
    missing_rows: list[dict[str, str]] = []
    matched: set[str] = set()

    for case_id in sorted(set(fixed_by_id) & set(buggy_by_id)):
        matched.add(case_id)
        rows.append(
            row(
                name,
                case_id,
                "F2P_OK",
                "explicit_case_pair",
                "explicit_fail",
                "explicit_pass",
                buggy_by_id[case_id].line,
                fixed_by_id[case_id].line,
            )
        )

    unmatched_fixed = [ev for ev in fixed_passes if ev.case_id not in matched]
    unmatched_buggy = [ev for ev in buggy_fails if ev.case_id not in matched]

    if len(unmatched_fixed) == 1 and len(unmatched_buggy) == 1:
        f_ev = unmatched_fixed[0]
        b_ev = unmatched_buggy[0]
        matched.add(f_ev.case_id)
        matched.add(b_ev.case_id)
        rows.append(
            row(
                name,
                f_ev.case_id,
                "F2P_OK",
                "single_unmatched_pass_fail_pair",
                "explicit_fail_singleton",
                "explicit_pass_singleton",
                b_ev.line,
                f_ev.line,
            )
        )
        unmatched_fixed = []
        unmatched_buggy = []

    for b_ev in unmatched_buggy:
        if has_fixed_global_pass:
            final_row = row(
                name,
                b_ev.case_id,
                "F2P_RECOVERED",
                "fixed_global_pass",
                "explicit_fail",
                "global_pass",
                b_ev.line,
                fixed_global_line,
            )
            rows.append(final_row)
            missing_rows.append(
                missing_row(
                    name,
                    b_ev.case_id,
                    "fixed_pass",
                    "explicit_fail",
                    b_ev.line,
                    final_row["status"],
                    final_row["reason"],
                    final_row["fixed_evidence_kind"],
                    final_row["fixed_evidence"],
                )
            )
        else:
            final_row = row(
                name,
                b_ev.case_id,
                "NEEDS_FIXED_PASS",
                "fixed_side_has_no_pass_evidence",
                "explicit_fail",
                "missing",
                b_ev.line,
                "",
            )
            rows.append(final_row)
            missing_rows.append(
                missing_row(
                    name,
                    b_ev.case_id,
                    "fixed_pass",
                    "explicit_fail",
                    b_ev.line,
                    final_row["status"],
                    final_row["reason"],
                    "missing",
                    "",
                )
            )

    for f_ev in unmatched_fixed:
        if has_buggy_global_fail:
            final_row = row(
                name,
                f_ev.case_id,
                "F2P_RECOVERED",
                "buggy_global_fail",
                buggy_global_kind,
                "explicit_pass",
                buggy_global_line,
                f_ev.line,
            )
            rows.append(final_row)
            missing_rows.append(
                missing_row(
                    name,
                    f_ev.case_id,
                    "buggy_fail",
                    "explicit_pass",
                    f_ev.line,
                    final_row["status"],
                    final_row["reason"],
                    final_row["buggy_evidence_kind"],
                    final_row["buggy_evidence"],
                )
            )
        else:
            final_row = row(
                name,
                f_ev.case_id,
                "NEEDS_BUGGY_FAIL",
                "buggy_side_has_no_fail_evidence",
                "missing",
                "explicit_pass",
                "",
                f_ev.line,
            )
            rows.append(final_row)
            missing_rows.append(
                missing_row(
                    name,
                    f_ev.case_id,
                    "buggy_fail",
                    "explicit_pass",
                    f_ev.line,
                    final_row["status"],
                    final_row["reason"],
                    "missing",
                    "",
                )
            )

    if not rows and has_fixed_global_pass and has_buggy_global_fail:
        rows.append(
            row(
                name,
                "__global__",
                "F2P_RECOVERED",
                "global_fail_to_global_pass",
                buggy_global_kind,
                "global_pass",
                buggy_global_line,
                fixed_global_line,
            )
        )

    return rows, missing_rows


def write_csv(path: Path, rows: list[dict[str, str]]) -> None:
    fields = [
        "instance",
        "case_id",
        "status",
        "reason",
        "buggy_evidence_kind",
        "fixed_evidence_kind",
        "buggy_evidence",
        "fixed_evidence",
    ]
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def write_missing_csv(path: Path, rows: list[dict[str, str]]) -> None:
    fields = [
        "instance",
        "case_id",
        "missing_side",
        "observed_evidence_kind",
        "observed_evidence",
        "recovery_status",
        "recovery_reason",
        "recovery_evidence_kind",
        "recovery_evidence",
    ]
    with path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=DEFAULT_ROOT)
    ap.add_argument("--out-dir", type=Path, default=BASE_DIR)
    ap.add_argument("--only", nargs="*", default=[])
    args = ap.parse_args()

    tb_dirs = sorted(p for p in args.root.iterdir() if p.is_dir())
    if args.only:
        wanted = set(args.only)
        tb_dirs = [p for p in tb_dirs if p.name in wanted]

    all_rows: list[dict[str, str]] = []
    pre_repair_missing: list[dict[str, str]] = []
    for tb_dir in tb_dirs:
        rows, missing_rows = analyze_instance(tb_dir)
        all_rows.extend(rows)
        pre_repair_missing.extend(missing_rows)

    repaired = [
        r for r in all_rows
        if r["status"] in {"F2P_OK", "F2P_RECOVERED"}
    ]
    needs = [
        r for r in all_rows
        if r["status"].startswith("NEEDS_")
    ]

    args.out_dir.mkdir(parents=True, exist_ok=True)
    repaired_path = args.out_dir / "verilator_f2p_case_repaired.csv"
    pre_missing_path = args.out_dir / "verilator_f2p_case_missing_before_repair.csv"
    needs_path = args.out_dir / "verilator_f2p_case_needs_rerun.csv"
    summary_path = args.out_dir / "verilator_f2p_case_repair_summary.csv"
    write_csv(repaired_path, repaired)
    write_missing_csv(pre_missing_path, pre_repair_missing)
    write_csv(needs_path, needs)

    status_counts = Counter(r["status"] for r in all_rows)
    reason_counts = Counter((r["status"], r["reason"]) for r in all_rows)
    pre_missing_counts = Counter(r["missing_side"] for r in pre_repair_missing)
    with summary_path.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["status", "reason", "count"])
        w.writeheader()
        for (status, reason), count in sorted(reason_counts.items()):
            w.writerow({"status": status, "reason": reason, "count": count})

    print("=== case-level F2P repair summary ===")
    print(f"root: {args.root}")
    print(f"instances scanned: {len(tb_dirs)}")
    print(f"rows evaluated: {len(all_rows)}")
    for status, count in sorted(status_counts.items()):
        print(f"{status}: {count}")
    for missing_side, count in sorted(pre_missing_counts.items()):
        print(f"pre-repair missing {missing_side}: {count}")
    print(f"repaired/evaluable: {len(repaired)} -> {repaired_path}")
    print(f"pre-repair one-sided rows: {len(pre_repair_missing)} -> {pre_missing_path}")
    print(f"needs rerun/fix: {len(needs)} -> {needs_path}")
    print(f"summary: {summary_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

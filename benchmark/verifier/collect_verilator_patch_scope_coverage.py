#!/usr/bin/env python3
"""Collect patch-scoped HDL function/scope coverage.

Verilator's LCOV output in this dataset does not emit FN/FNDA function
records.  This script derives a patch-scoped function/scope view by mapping
patch-added source lines to their enclosing HDL scope and intersecting those
lines with LCOV DA counts.
"""

from __future__ import annotations

import argparse
import csv
import re
from pathlib import Path

from collect_verilator_patch_coverage import (
    ROOT,
    Exclusions,
    is_excluded,
    load_exclusions,
    parse_patch,
    rel_for_source,
    pct,
)


def strip_line_comment(line: str) -> str:
    return line.split("//", 1)[0]


def decl_name(kind: str, text: str) -> str:
    before_paren = text.split("(", 1)[0].replace(";", " ")
    after_kind = re.split(rf"\b{kind}\b", before_paren, maxsplit=1)[-1]
    tokens = [tok for tok in re.split(r"\s+", after_kind.strip()) if tok]
    skip = {"automatic", "static", "virtual", "signed", "unsigned"}
    candidates = [tok for tok in tokens if tok not in skip and not tok.startswith("[")]
    return candidates[-1] if candidates else f"{kind}@unknown"


def scope_map(source_path: Path) -> dict[int, tuple[str, str, int]]:
    lines = source_path.read_text(errors="replace").splitlines()
    active: list[dict[str, object]] = []
    by_line: dict[int, tuple[str, str, int]] = {}
    block_depth = 0

    for line_no, raw in enumerate(lines, 1):
        text = strip_line_comment(raw)
        stripped = text.strip()

        m = re.match(r"\s*(module|interface|package|class|program)\s+([A-Za-z_$][\w$]*)", text)
        if m:
            active.append({"kind": m.group(1), "name": m.group(2), "start": line_no})

        m = re.match(r"\s*(function|task)\b", text)
        if m:
            kind = m.group(1)
            active.append({"kind": kind, "name": decl_name(kind, text), "start": line_no})

        m = re.match(r"\s*(always_ff|always_comb|always_latch|always|initial|final)\b", text)
        if m:
            kind = m.group(1)
            begins = len(re.findall(r"\bbegin\b", text))
            ends = len(re.findall(r"\bend\b", text))
            target_depth = block_depth + max(1, begins - ends)
            active.append({
                "kind": kind,
                "name": f"{kind}@{line_no}",
                "start": line_no,
                "target_depth": target_depth,
            })

        if active:
            scope = active[-1]
            by_line[line_no] = (
                str(scope["kind"]),
                str(scope["name"]),
                int(scope["start"]),
            )
        else:
            by_line[line_no] = ("file", source_path.name, 1)

        block_depth += len(re.findall(r"\bbegin\b", text))
        block_depth -= len(re.findall(r"\bend\b", text))
        if block_depth < 0:
            block_depth = 0

        explicit_end = {
            "endmodule": "module",
            "endinterface": "interface",
            "endpackage": "package",
            "endclass": "class",
            "endprogram": "program",
            "endfunction": "function",
            "endtask": "task",
        }
        for token, kind in explicit_end.items():
            if re.search(rf"\b{token}\b", stripped):
                for idx in range(len(active) - 1, -1, -1):
                    if active[idx].get("kind") == kind:
                        del active[idx:]
                        break

        while active and active[-1].get("kind") in {"always_ff", "always_comb", "always_latch", "always", "initial", "final"}:
            target_depth = int(active[-1].get("target_depth", 0))
            if block_depth < target_depth:
                active.pop()
            else:
                break

    return by_line


def parse_lcov_counts(case: str, patch_files: set[str]) -> dict[tuple[str, int], int]:
    case_dir = ROOT / "testbench_verilator" / case
    info_path = case_dir / "coverage.info"
    if not info_path.exists():
        info_path = case_dir / "verilator_fixed_coverage.info"
    counts: dict[tuple[str, int], int] = {}
    if not info_path.exists():
        return counts

    current: str | None = None
    for raw in info_path.read_text(errors="replace").splitlines():
        if raw.startswith("SF:"):
            current = rel_for_source(raw[3:], patch_files)
            continue
        if current is None or not raw.startswith("DA:"):
            continue
        parts = raw[3:].split(",")
        if len(parts) < 2:
            continue
        try:
            counts[(current, int(parts[0]))] = int(parts[1])
        except ValueError:
            continue
    return counts


def collect_case_scopes(case: str, exclusions: Exclusions) -> list[dict[str, str | int]]:
    case_dir = ROOT / "testbench_verilator" / case
    added, _ = parse_patch(ROOT / "patches" / f"{case}.patch")
    counts = parse_lcov_counts(case, set(added))
    rows_by_scope: dict[tuple[str, str, str, int], dict[str, object]] = {}

    for rel, lines in added.items():
        source_path = case_dir / "snapshot_scratch" / rel
        if not source_path.exists():
            continue
        scopes = scope_map(source_path)
        for line_no in sorted(lines):
            if is_excluded(exclusions, case, rel, line_no):
                continue
            if (rel, line_no) not in counts:
                continue
            kind, name, start = scopes.get(line_no, ("file", Path(rel).name, 1))
            key = (case, rel, f"{kind} {name}", start)
            row = rows_by_scope.setdefault(key, {
                "case": case,
                "file": rel,
                "scope": f"{kind} {name}",
                "scope_start": start,
                "patch_lcov_lines": 0,
                "patch_lcov_hits": 0,
                "missing_patch_lines": [],
            })
            row["patch_lcov_lines"] = int(row["patch_lcov_lines"]) + 1
            if counts[(rel, line_no)] > 0:
                row["patch_lcov_hits"] = int(row["patch_lcov_hits"]) + 1
            else:
                row["missing_patch_lines"].append(str(line_no))  # type: ignore[index]

    rows: list[dict[str, str | int]] = []
    for row in rows_by_scope.values():
        hit = int(row["patch_lcov_hits"])
        total = int(row["patch_lcov_lines"])
        rows.append({
            "case": str(row["case"]),
            "file": str(row["file"]),
            "scope": str(row["scope"]),
            "scope_start": int(row["scope_start"]),
            "scope_hit": 1 if hit > 0 else 0,
            "scope_full": 1 if total > 0 and hit == total else 0,
            "patch_lcov_hits": hit,
            "patch_lcov_lines": total,
            "patch_lcov_pct": pct(hit, total),
            "missing_patch_lines": ";".join(row["missing_patch_lines"]),  # type: ignore[arg-type]
        })
    return sorted(rows, key=lambda row: (str(row["case"]), str(row["file"]), int(row["scope_start"])))


def default_cases() -> list[str]:
    return sorted(
        p.name
        for p in (ROOT / "testbench_verilator").iterdir()
        if p.is_dir()
        and (ROOT / "patches" / f"{p.name}.patch").exists()
        and ((p / "coverage.info").exists() or (p / "verilator_fixed_coverage.info").exists())
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("cases", nargs="*")
    parser.add_argument("--csv", default="patch_only_scope_coverage.csv")
    parser.add_argument("--summary-csv", default="patch_only_scope_coverage_summary.csv")
    parser.add_argument("--function-csv", default="patch_only_function_coverage.csv")
    parser.add_argument("--function-summary-csv", default="patch_only_function_coverage_summary.csv")
    parser.add_argument("--exclude-csv")
    args = parser.parse_args()

    exclusions = load_exclusions(args.exclude_csv)
    cases = args.cases or default_cases()
    rows = [row for case in cases for row in collect_case_scopes(case, exclusions)]

    fields = [
        "case",
        "file",
        "scope",
        "scope_start",
        "scope_hit",
        "scope_full",
        "patch_lcov_hits",
        "patch_lcov_lines",
        "patch_lcov_pct",
        "missing_patch_lines",
    ]
    out_path = ROOT / args.csv
    with out_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)

    by_case: dict[str, list[dict[str, str | int]]] = {}
    for row in rows:
        by_case.setdefault(str(row["case"]), []).append(row)

    summary_fields = [
        "case",
        "scope_hit",
        "scope_total",
        "scope_hit_pct",
        "scope_full",
        "scope_full_pct",
        "patch_lcov_hits",
        "patch_lcov_lines",
        "patch_lcov_pct",
    ]
    summary_rows: list[dict[str, str | int]] = []
    for case, case_rows in sorted(by_case.items()):
        scope_total = len(case_rows)
        scope_hit = sum(int(row["scope_hit"]) for row in case_rows)
        scope_full = sum(int(row["scope_full"]) for row in case_rows)
        line_hit = sum(int(row["patch_lcov_hits"]) for row in case_rows)
        line_total = sum(int(row["patch_lcov_lines"]) for row in case_rows)
        summary_rows.append({
            "case": case,
            "scope_hit": scope_hit,
            "scope_total": scope_total,
            "scope_hit_pct": pct(scope_hit, scope_total),
            "scope_full": scope_full,
            "scope_full_pct": pct(scope_full, scope_total),
            "patch_lcov_hits": line_hit,
            "patch_lcov_lines": line_total,
            "patch_lcov_pct": pct(line_hit, line_total),
        })

    total_scope = len(rows)
    total_scope_hit = sum(int(row["scope_hit"]) for row in rows)
    total_scope_full = sum(int(row["scope_full"]) for row in rows)
    total_line_hit = sum(int(row["patch_lcov_hits"]) for row in rows)
    total_line = sum(int(row["patch_lcov_lines"]) for row in rows)
    summary_rows.append({
        "case": "TOTAL",
        "scope_hit": total_scope_hit,
        "scope_total": total_scope,
        "scope_hit_pct": pct(total_scope_hit, total_scope),
        "scope_full": total_scope_full,
        "scope_full_pct": pct(total_scope_full, total_scope),
        "patch_lcov_hits": total_line_hit,
        "patch_lcov_lines": total_line,
        "patch_lcov_pct": pct(total_line_hit, total_line),
    })

    summary_path = ROOT / args.summary_csv
    with summary_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=summary_fields)
        writer.writeheader()
        writer.writerows(summary_rows)

    print(f"Saved: {out_path}")
    print(f"Saved summary: {summary_path}")
    print(",".join(summary_fields))
    for row in summary_rows:
        print(",".join(str(row[field]) for field in summary_fields))

    function_fields = [
        "case",
        "file",
        "function_scope",
        "scope_start",
        "function_hit",
        "patch_lcov_hits",
        "patch_lcov_lines",
        "patch_lcov_pct",
    ]
    function_path = ROOT / args.function_csv
    with function_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=function_fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({
                "case": row["case"],
                "file": row["file"],
                "function_scope": row["scope"],
                "scope_start": row["scope_start"],
                "function_hit": row["scope_hit"],
                "patch_lcov_hits": row["patch_lcov_hits"],
                "patch_lcov_lines": row["patch_lcov_lines"],
                "patch_lcov_pct": row["patch_lcov_pct"],
            })

    function_summary_fields = [
        "case",
        "function_hit",
        "function_total",
        "function_hit_pct",
    ]
    function_summary_path = ROOT / args.function_summary_csv
    with function_summary_path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=function_summary_fields)
        writer.writeheader()
        for row in summary_rows:
            writer.writerow({
                "case": row["case"],
                "function_hit": row["scope_hit"],
                "function_total": row["scope_total"],
                "function_hit_pct": row["scope_hit_pct"],
            })
    print(f"Saved function coverage: {function_path}")
    print(f"Saved function summary: {function_summary_path}")


if __name__ == "__main__":
    main()

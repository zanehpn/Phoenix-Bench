#!/usr/bin/env python3
"""Classify each patch into T1/T2/T3 tiers, considering only HDL files
(.v, .sv, .vh, .svh).

Tier definition (from Phoenix-bench Sec 4.5):
  T1 Easy:   single hunk, single module/file
  T2 Medium: 2-5 hunks within a single file
  T3 Hard:   >=6 hunks, OR multi-file, OR cross-hierarchy edits
"""

from __future__ import annotations

import json
import re
from collections import defaultdict
from pathlib import Path

PATCH_DIR = Path("/workspace/phoenix-bench/HDL_verified_new/patches")
SNAPSHOT_DIR = Path("/workspace/phoenix-bench/HDL_agent_eval/benchmark_codex/snapshots")
OUT_JSON = Path("/workspace/phoenix-bench/HDL_verified_new/patch_complexity.json")
OUT_TSV = Path("/workspace/phoenix-bench/HDL_verified_new/patch_complexity.tsv")
OUT_SUMMARY = Path("/workspace/phoenix-bench/HDL_verified_new/patch_complexity_summary.txt")

HDL_EXTS = (".v", ".sv", ".vh", ".svh")

DIFF_RE = re.compile(r"^diff --git a/(.+?) b/(.+?)$")
HUNK_RE = re.compile(r"^@@ -\d+(?:,\d+)? \+\d+(?:,\d+)? @@")


def is_hdl(path: str) -> bool:
    return path.lower().endswith(HDL_EXTS)


def parse_patch(text: str):
    """Return list of (file_path, hunk_count) for HDL files only."""
    files: dict[str, int] = {}
    current_hdl = None

    for line in text.splitlines():
        m = DIFF_RE.match(line)
        if m:
            path_b = m.group(2)
            current_hdl = path_b if is_hdl(path_b) else None
            if current_hdl is not None:
                files.setdefault(current_hdl, 0)
            continue
        if current_hdl is not None and HUNK_RE.match(line):
            files[current_hdl] += 1

    return files


def top_dir(path: str) -> str:
    parts = Path(path).parts
    return parts[0] if parts else ""


def classify(files: dict[str, int]) -> tuple[str, str]:
    """Return (tier, reason). Tier in {T1,T2,T3,SKIP}."""
    if not files:
        return "SKIP", "no HDL files touched"

    n_files = len(files)
    total_hunks = sum(files.values())
    top_dirs = {top_dir(p) for p in files}

    if total_hunks >= 6:
        return "T3", f">=6 hunks ({total_hunks})"
    if n_files > 1:
        if len(top_dirs) > 1:
            return "T3", f"multi-file across {len(top_dirs)} top-level dirs (cross-hierarchy)"
        return "T3", f"multi-file ({n_files} files)"

    # single HDL file from here
    only_file, hunks = next(iter(files.items()))
    if hunks == 1:
        return "T1", "single hunk, single file"
    if 2 <= hunks <= 5:
        return "T2", f"{hunks} hunks in single file"
    return "T3", f"{hunks} hunks"  # safety net


def main() -> None:
    rows = []
    tier_counts: dict[str, int] = defaultdict(int)
    valid_cases = {p.name for p in SNAPSHOT_DIR.iterdir() if p.is_dir()}

    for patch_path in sorted(PATCH_DIR.glob("*.patch")):
        case = patch_path.stem
        if case not in valid_cases:
            continue
        text = patch_path.read_text(errors="replace")
        files = parse_patch(text)
        tier, reason = classify(files)
        n_files = len(files)
        n_hunks = sum(files.values())
        rows.append(
            {
                "case": case,
                "tier": tier,
                "n_hdl_files": n_files,
                "n_hunks": n_hunks,
                "files": files,
                "reason": reason,
            }
        )
        tier_counts[tier] += 1

    OUT_JSON.write_text(json.dumps(rows, indent=2))

    with OUT_TSV.open("w") as fh:
        fh.write("case\ttier\tn_hdl_files\tn_hunks\treason\n")
        for r in rows:
            fh.write(f"{r['case']}\t{r['tier']}\t{r['n_hdl_files']}\t{r['n_hunks']}\t{r['reason']}\n")

    total = len(rows)
    lines = ["Phoenix-bench patch complexity classification (HDL files only: .v/.sv/.vh/.svh)"]
    lines.append(f"total cases: {total}")
    for tier in ("T1", "T2", "T3", "SKIP"):
        c = tier_counts.get(tier, 0)
        pct = (c * 100.0 / total) if total else 0.0
        lines.append(f"  {tier}: {c}  ({pct:.1f}%)")
    lines.append("")
    lines.append("Tier rules:")
    lines.append("  T1 Easy   : single hunk, single HDL file")
    lines.append("  T2 Medium : 2-5 hunks within a single HDL file")
    lines.append("  T3 Hard   : >=6 hunks, OR multi-file, OR cross-top-dir (cross-hierarchy)")
    lines.append("  SKIP      : patch touches no HDL file")
    OUT_SUMMARY.write_text("\n".join(lines) + "\n")
    print("\n".join(lines))


if __name__ == "__main__":
    main()

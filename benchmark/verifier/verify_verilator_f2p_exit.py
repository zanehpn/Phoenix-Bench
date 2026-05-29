#!/usr/bin/env python3
"""
Verify Verilator fail-to-pass using run_verilator.sh *exit code* only.

No string grep on output. Contract per testbench:
  - Buggy state (pre-patch): `bash run_verilator.sh` exits non-zero.
  - Patched state (post-patch): `bash run_verilator.sh` exits zero.

To support this contract the tb must use `$fatal(...)` (which Verilator maps
to a non-zero simulation exit) on the FAIL path and `$finish` on the PASS
path. The convert_to_verilator script sanitizer lifts legacy
`$display("FAIL..."); $finish;` into `$fatal(1, "FAIL...");`.

Verdict map:
  F2P_OK          : buggy exit != 0 AND patched exit == 0
  BUGGY_NOT_FAIL  : buggy exit == 0 (patch-irrelevant tb)
  PATCHED_NOT_PASS: patched exit != 0
  PATCH_FAIL      : forward-apply patch failed
  RESTORE_FAIL    : git-reset of snapshot failed
  NO_RUN/NO_PATCH/NO_SNAPSHOT : missing inputs
  SKIP_NA         : per-tb .verilator_skip marker present
  TIMEOUT         : run exceeded timeout
"""

import os
import sys
import csv
import time
import argparse
import subprocess
from pathlib import Path

BASE_DIR = Path("/workspace/phoenix-bench/HDL_verified_new")
TB_DIR   = BASE_DIR / "testbench"
SNAP_DIR = BASE_DIR / "snapshots"
PATCH_DIR= BASE_DIR / "patches"
TIMEOUT  = 1200


def run_tb(tb_path: Path, timeout=TIMEOUT):
    """Run run_verilator.sh; return (exit_code, timed_out)."""
    # clean stale logs
    for log in ("simv.log", "verilator.log", "verilator_build.log"):
        p = tb_path / log
        if p.exists():
            try: p.unlink()
            except: pass
    try:
        r = subprocess.run(
            ["bash", "run_verilator.sh"],
            cwd=str(tb_path),
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            timeout=timeout,
        )
        return r.returncode, False
    except subprocess.TimeoutExpired:
        return -1, True
    except Exception:
        return -2, False


def git_reset(snap_path: Path) -> bool:
    if not (snap_path / ".git").is_dir():
        return True  # no git, nothing to do
    try:
        r1 = subprocess.run(["git", "reset", "--hard", "HEAD"],
                           cwd=str(snap_path), stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=30)
        r2 = subprocess.run(["git", "clean", "-fd"],
                           cwd=str(snap_path), stdout=subprocess.DEVNULL,
                           stderr=subprocess.DEVNULL, timeout=30)
        return r1.returncode == 0 and r2.returncode == 0
    except Exception:
        return False


def apply_patch(snap_path: Path, patch_file: Path) -> bool:
    # -N (--forward) disables patch's auto-reverse heuristic so a snapshot
    # already in patched state doesn't have the patch silently reversed.
    try:
        r = subprocess.run(
            ["patch", "-p1", "-N", "--batch", "--fuzz=5", "-i", str(patch_file)],
            cwd=str(snap_path), stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL, timeout=60)
        return r.returncode in (0, 1)
    except Exception:
        return False


def verify_one(name: str):
    tb_path    = TB_DIR    / name
    snap_path  = SNAP_DIR  / name
    patch_file = PATCH_DIR / f"{name}.patch"

    rec = dict(instance=name, verdict="",
               buggy_exit=0, patched_exit=0,
               note="", duration_s=0.0)

    if (tb_path / ".verilator_skip").exists():
        rec["verdict"] = "SKIP_NA"
        try:
            rec["note"] = (tb_path / ".verilator_skip").read_text(errors="replace").strip().splitlines()[0][:120]
        except Exception: pass
        return rec
    if not (tb_path / "run_verilator.sh").exists():
        rec["verdict"] = "NO_RUN";      return rec
    if not patch_file.exists():
        rec["verdict"] = "NO_PATCH";    return rec
    if not snap_path.is_dir():
        rec["verdict"] = "NO_SNAPSHOT"; return rec

    t0 = time.time()

    # Start from clean snapshot (buggy state == HEAD)
    if not git_reset(snap_path):
        rec["verdict"] = "RESTORE_FAIL"
        rec["note"]    = "pre-run git reset failed"
        rec["duration_s"] = round(time.time()-t0, 1)
        return rec

    # Step 1: buggy run
    ec_b, to_b = run_tb(tb_path)
    if to_b:
        rec["verdict"] = "TIMEOUT"; rec["note"] = "timeout on buggy"
        rec["duration_s"] = round(time.time()-t0, 1); return rec
    rec["buggy_exit"] = ec_b

    # Step 2: forward-apply patch
    if not apply_patch(snap_path, patch_file):
        rec["verdict"] = "PATCH_FAIL"
        rec["note"]    = "forward-apply failed"
        git_reset(snap_path)
        rec["duration_s"] = round(time.time()-t0, 1)
        return rec

    # Step 3: patched run
    try:
        ec_p, to_p = run_tb(tb_path)
    finally:
        git_reset(snap_path)  # always restore via git

    if to_p:
        rec["verdict"] = "TIMEOUT"; rec["note"] = "timeout on patched"
        rec["duration_s"] = round(time.time()-t0, 1); return rec
    rec["patched_exit"] = ec_p

    # Verdict: F2P means buggy exit!=0, patched exit==0
    if ec_b == 0:
        rec["verdict"] = "BUGGY_NOT_FAIL"
        rec["note"]    = "buggy run exited 0 (expected non-zero)"
    elif ec_p != 0:
        rec["verdict"] = "PATCHED_NOT_PASS"
        rec["note"]    = f"patched run exit={ec_p}"
    else:
        rec["verdict"] = "F2P_OK"

    rec["duration_s"] = round(time.time()-t0, 1)
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*")
    ap.add_argument("--skip", nargs="*", default=[])
    ap.add_argument("--out",  default=str(BASE_DIR / "verilator_f2p_exit_results.csv"))
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    names = sorted([p.name for p in TB_DIR.iterdir()
                    if p.is_dir() and not p.name.startswith("__")])
    if args.only:
        names = [n for n in names if n in set(args.only)]
    if args.skip:
        names = [n for n in names if n not in set(args.skip)]
    if args.limit:
        names = names[:args.limit]

    hdr = "{:<55} {:>9} {:>9} {:>20} {:>7}".format(
        "instance", "buggy_ec", "patch_ec", "verdict", "sec")
    print(hdr); print("-" * len(hdr))

    rows = []
    for nm in names:
        rec = verify_one(nm)
        print("{:<55} {:>9} {:>9} {:>20} {:>7}".format(
            rec["instance"], rec["buggy_exit"], rec["patched_exit"],
            rec["verdict"], rec["duration_s"]), flush=True)
        rows.append(rec)
        with open(args.out, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader(); w.writerows(rows)

    verdicts = {}
    for r in rows:
        verdicts[r["verdict"]] = verdicts.get(r["verdict"], 0) + 1
    print("\n=== SUMMARY (exit-code based) ===")
    for k in sorted(verdicts):
        print(f"  {k:<20} {verdicts[k]}")
    print(f"Results: {args.out}")


if __name__ == "__main__":
    main()

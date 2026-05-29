#!/usr/bin/env python3
"""
Verify Verilator fail-to-pass (F2P) property per testbench.

For each testbench dir that has a run_verilator.sh:
  1. Assume snapshot is in BUGGY (pre-patch) state.
  2. Run run_verilator.sh -> record PASS/FAIL counts (buggy_out).
  3. Forward-apply patch.
  4. Run run_verilator.sh -> record PASS/FAIL counts (patched_out).
  5. Reverse-apply patch to restore BUGGY state.

Per-instance verdict:
  - "F2P_OK"          : buggy has FAIL>0 AND patched has PASS>0 AND patched FAIL==0.
  - "BUGGY_NOT_FAIL"  : buggy didn't fail (no FAIL markers produced).
  - "PATCHED_NOT_PASS": patched didn't pass (no PASS markers or still has FAIL).
  - "PATCH_FAIL"      : forward-apply patch failed.
  - "RESTORE_FAIL"    : reverse-apply patch failed (snapshot may be corrupted).
  - "NO_RUN"          : no run_verilator.sh.
  - "NO_PATCH"        : no patch file.
  - "NO_SNAPSHOT"     : no snapshot dir.
  - "TIMEOUT"         : run exceeded timeout.
  - "BUILD_FAIL"      : Verilator build failed (treated as FAIL for buggy state
                         - which is fine if buggy build legitimately fails - but
                         a build failure on patched state is a real problem).

Output: CSV at verilator_f2p_results.csv and console table.
"""

import os
import re
import sys
import csv
import time
import argparse
import subprocess
from pathlib import Path

BASE_DIR  = Path("/workspace/phoenix-bench/HDL_verified_new")
TB_DIR    = BASE_DIR / "testbench"
SNAP_DIR  = BASE_DIR / "snapshots"
PATCH_DIR = BASE_DIR / "patches"
TIMEOUT   = 1200  # Verilator builds can be slow for complex RISC-V cores

# Match PASS/FAIL verdict markers. The PASS side is permissive (extra
# matches on summary lines like "ALL TESTS PASSED" are harmless — we only
# care that PASS>0). The FAIL side is strict: we must NOT match "FAILED"
# inside count summaries like "47 PASSED, 0 FAILED" or an F2P_OK case
# would be flipped to PATCHED_NOT_PASS.
PASS_RE = re.compile(r'\bPASS(?:ED)?\b|\[PASS\]')
FAIL_RE = re.compile(r'\bFAIL\b|\[FAIL\]')
# Verilator runtime failure signals (all definitive):
#   $fatal   -> "[t] %Fatal: ..."
#   $stop    -> "[t] %Error: ... Verilog $stop"
#   Assertion failure / other runtime $stop -> "Aborting..."
# Each independent $fatal/$stop usually emits one %Fatal: and/or one
# "Verilog $stop" line, so taking max across markers avoids double-count.
VLT_FATAL_RE = re.compile(r'%Fatal:')
VLT_STOP_RE  = re.compile(r'Verilog \$stop')


def count_pass_fail(text: str):
    p = len(PASS_RE.findall(text))
    f_tag   = len(FAIL_RE.findall(text))
    f_fatal = len(VLT_FATAL_RE.findall(text))
    f_stop  = len(VLT_STOP_RE.findall(text))
    # A tb may use any of: $display("FAIL:"), $fatal, or $stop.
    # Each style is one failure; take max so mixed-style tbs aren't
    # double-counted, but no-FAIL-but-$stop tbs still count.
    return p, max(f_tag, f_fatal, f_stop)


def run_verilator_tb(tb_path: Path, timeout=TIMEOUT):
    """Run run_verilator.sh and return (output, timed_out, build_failed)."""
    # Clean stale logs
    for log in ("simv.log", "verilator.log", "verilator_build.log"):
        p = tb_path / log
        if p.exists():
            try: p.unlink()
            except: pass
    try:
        r = subprocess.run(
            ["bash", "run_verilator.sh"],
            cwd=str(tb_path),
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            timeout=timeout,
        )
        out = r.stdout.decode("utf-8", errors="replace")
    except subprocess.TimeoutExpired as e:
        out = (e.stdout or b"").decode("utf-8", errors="replace") if e.stdout else ""
        return out, True, False
    except Exception as ex:
        return f"ERROR: {ex}", False, False

    build_failed = not (tb_path / "obj_dir" / "simv_vlt").exists()
    # NOTE: run_verilator.sh pipes stdout through `tee simv.log`, so the
    # captured subprocess stdout already contains the PASS/FAIL markers.
    # Do NOT append simv.log separately — that double-counts every marker.
    return out, False, build_failed


def do_patch(snap_path: Path, patch_file: Path, reverse: bool) -> bool:
    """Apply a patch. Returns True if at least some hunks succeeded.

    GNU patch exit codes: 0 = all hunks applied, 1 = some hunks failed but
    others succeeded, 2 = serious error (missing input, etc). We accept 0/1
    because many snapshots have partial mismatches on non-RTL files (README,
    CHANGELOG) that still leave the RTL behavior correctly patched, which is
    what the testbench actually checks.
    """
    cmd = ["patch", "-p1", "--batch", "--fuzz=3", "-i", str(patch_file)]
    if reverse:
        cmd.insert(1, "-R")
    try:
        r = subprocess.run(cmd, cwd=str(snap_path),
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
        return r.returncode in (0, 1)
    except Exception:
        return False


def verify_one(name: str):
    tb_path    = TB_DIR    / name
    snap_path  = SNAP_DIR  / name
    patch_file = PATCH_DIR / f"{name}.patch"

    rec = dict(instance=name,
               verdict="",
               pass_buggy=0, fail_buggy=0,
               pass_patched=0, fail_patched=0,
               buggy_build="", patched_build="",
               note="", duration_s=0.0)

    skip_marker = tb_path / ".verilator_skip"
    if skip_marker.exists():
        rec["verdict"] = "SKIP_NA"
        try:
            rec["note"] = skip_marker.read_text(errors="replace").strip().splitlines()[0][:120]
        except Exception:
            rec["note"] = "verilator-not-applicable"
        return rec
    run_vlt = tb_path / "run_verilator.sh"
    if not run_vlt.exists():
        rec["verdict"] = "NO_RUN";      return rec
    if not patch_file.exists():
        rec["verdict"] = "NO_PATCH";    return rec
    if not snap_path.is_dir():
        rec["verdict"] = "NO_SNAPSHOT"; return rec

    t0 = time.time()

    # --- Step 0: Force snapshot to buggy (initial) state.
    # If a prior aborted run left the snapshot with the patch applied,
    # the "buggy run" would actually exercise the patched design and
    # the verdict logic inverts (Pb high, Fb zero). Hard-reset first.
    if (snap_path / ".git").is_dir():
        try:
            subprocess.run(["git", "reset", "--hard", "HEAD"],
                           cwd=str(snap_path), stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, timeout=30)
            subprocess.run(["git", "clean", "-fd"],
                           cwd=str(snap_path), stdout=subprocess.PIPE,
                           stderr=subprocess.PIPE, timeout=30)
        except Exception:
            pass

    # --- Step 1: Run on buggy (current) state
    out_b, to_b, bf_b = run_verilator_tb(tb_path)
    if to_b:
        rec["verdict"] = "TIMEOUT"; rec["note"] = "timeout on buggy"
        rec["duration_s"] = round(time.time()-t0, 1); return rec
    pb, fb = count_pass_fail(out_b)
    rec["pass_buggy"], rec["fail_buggy"] = pb, fb
    rec["buggy_build"] = "FAIL" if bf_b else "OK"

    # --- Step 2: Forward-apply patch
    if not do_patch(snap_path, patch_file, reverse=False):
        rec["verdict"] = "PATCH_FAIL"
        rec["note"]    = "forward-apply failed"
        rec["duration_s"] = round(time.time()-t0, 1)
        return rec

    # --- Step 3: Run on patched state
    try:
        out_p, to_p, bf_p = run_verilator_tb(tb_path)
    finally:
        # --- Step 4: always attempt restore.
        # Prefer git-based restore (robust) when snapshot is a git repo;
        # fall back to patch -R otherwise.
        restored = False
        if (snap_path / ".git").is_dir():
            try:
                r1 = subprocess.run(["git", "reset", "--hard", "HEAD"],
                                   cwd=str(snap_path), stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, timeout=30)
                r2 = subprocess.run(["git", "clean", "-fd"],
                                   cwd=str(snap_path), stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, timeout=30)
                restored = (r1.returncode == 0 and r2.returncode == 0)
            except Exception:
                restored = False
        if not restored:
            restored = do_patch(snap_path, patch_file, reverse=True)

    if to_p:
        rec["verdict"] = "TIMEOUT"; rec["note"] = "timeout on patched"
        rec["duration_s"] = round(time.time()-t0, 1); return rec
    pp, fp = count_pass_fail(out_p)
    rec["pass_patched"], rec["fail_patched"] = pp, fp
    rec["patched_build"] = "FAIL" if bf_p else "OK"

    if not restored:
        rec["verdict"] = "RESTORE_FAIL"
        rec["note"]    = "snapshot may be corrupted; reverse-apply failed"
        rec["duration_s"] = round(time.time()-t0, 1)
        return rec

    # --- Step 5: verdict
    # F2P means:
    #   buggy state had at least one FAIL marker (demonstrates the bug)
    #   patched state has >=1 PASS and 0 FAIL markers
    if fb == 0:
        rec["verdict"] = "BUGGY_NOT_FAIL"
        rec["note"]    = "buggy run produced no FAIL markers"
    elif pp == 0 or fp > 0:
        rec["verdict"] = "PATCHED_NOT_PASS"
        rec["note"]    = f"patched run: PASS={pp} FAIL={fp}"
    else:
        rec["verdict"] = "F2P_OK"

    rec["duration_s"] = round(time.time()-t0, 1)
    return rec


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", nargs="*", help="restrict to given testbench names")
    ap.add_argument("--skip", nargs="*", default=[], help="skip these names")
    ap.add_argument("--out",  default=str(BASE_DIR / "verilator_f2p_results.csv"))
    ap.add_argument("--limit", type=int, default=0, help="stop after N testbenches")
    args = ap.parse_args()

    names = sorted([p.name for p in TB_DIR.iterdir()
                    if p.is_dir() and not p.name.startswith("__")])
    if args.only:
        names = [n for n in names if n in set(args.only)]
    if args.skip:
        names = [n for n in names if n not in set(args.skip)]
    if args.limit:
        names = names[:args.limit]

    hdr = "{:<55} {:>8} {:>8} {:>8} {:>8} {:>10} {:>10} {:>18} {:>7}".format(
        "instance", "Pb", "Fb", "Pp", "Fp", "buggy_bld", "patch_bld", "verdict", "sec")
    print(hdr); print("-" * len(hdr))

    rows = []
    for nm in names:
        rec = verify_one(nm)
        print("{:<55} {:>8} {:>8} {:>8} {:>8} {:>10} {:>10} {:>18} {:>7}".format(
            rec["instance"],
            rec["pass_buggy"], rec["fail_buggy"],
            rec["pass_patched"], rec["fail_patched"],
            rec["buggy_build"], rec["patched_build"],
            rec["verdict"], rec["duration_s"]), flush=True)
        rows.append(rec)
        # Write incrementally so early Ctrl+C still keeps results
        with open(args.out, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader(); w.writerows(rows)

    # Summary
    verdicts = {}
    for r in rows:
        verdicts[r["verdict"]] = verdicts.get(r["verdict"], 0) + 1
    print("\n=== SUMMARY ===")
    for k in sorted(verdicts):
        print(f"  {k:<20} {verdicts[k]}")
    print(f"Results: {args.out}")


if __name__ == "__main__":
    main()

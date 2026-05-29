#!/usr/bin/env python3
"""
Count fail-to-pass test cases for each testbench.

Snapshots are at base_commit (pre-patch, buggy state).
Workflow per testbench:
1. Run on buggy snapshot (original) -> count PASS/FAIL
2. Forward-apply patch -> run on fixed code -> count PASS/FAIL
3. Reverse-apply patch to restore original state
4. fail_to_pass = PASS(patched) - PASS(buggy)
"""

import os
import subprocess
import re
import csv
import sys

BASE_DIR = "/workspace/phoenix-bench/HDL_verified_new"
TB_DIR = os.path.join(BASE_DIR, "testbench")
SNAP_DIR = os.path.join(BASE_DIR, "snapshots")
PATCH_DIR = os.path.join(BASE_DIR, "patches")
TIMEOUT = 120


def count_pass_fail(output_text):
    """Count PASS and FAIL test cases from simulation output."""
    pass_count = 0
    fail_count = 0
    for line in output_text.split('\n'):
        stripped = line.strip()
        if re.match(r'^(\[PASS\]|PASS:)', stripped):
            pass_count += 1
        elif re.match(r'^(\[FAIL\]|FAIL:)', stripped):
            fail_count += 1
    return pass_count, fail_count


def run_testbench(tb_path):
    """Run testbench and return combined output."""
    simv_log = os.path.join(tb_path, 'simv.log')
    if os.path.exists(simv_log):
        os.remove(simv_log)

    try:
        result = subprocess.run(
            ['bash', 'run.sh'],
            cwd=tb_path,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=TIMEOUT
        )
        output = result.stdout.decode('utf-8', errors='replace') + '\n' + \
                 result.stderr.decode('utf-8', errors='replace')
    except subprocess.TimeoutExpired:
        output = "TIMEOUT"
    except Exception as e:
        output = "ERROR: {}".format(e)

    if os.path.exists(simv_log):
        try:
            r = subprocess.run(
                ['strings', simv_log],
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
            )
            output += '\n' + r.stdout.decode('utf-8', errors='replace')
        except:
            pass

    return output


def do_patch(snap_path, patch_file, reverse=False):
    """Apply or reverse a patch. Returns True on success."""
    cmd = ['patch', '-p1', '--batch', '--fuzz=3', '-i', patch_file]
    if reverse:
        cmd.insert(1, '-R')
    try:
        result = subprocess.run(
            cmd, cwd=snap_path,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
        )
        return result.returncode == 0
    except:
        return False


def main():
    tb_names = sorted(os.listdir(TB_DIR))
    results = []

    fmt = "{:<55} {:>13} {:>12} {:>12} {:>12} {:>5}"
    print(fmt.format("Instance", "PASS(buggy)", "FAIL(buggy)", "PASS(patch)", "FAIL(patch)", "F2P"))
    print("-" * 115)

    for name in tb_names:
        tb_path = os.path.join(TB_DIR, name)
        if not os.path.isdir(tb_path):
            continue

        patch_file = os.path.join(PATCH_DIR, "{}.patch".format(name))
        snap_path = os.path.join(SNAP_DIR, name)

        if not os.path.isfile(patch_file) or not os.path.isdir(snap_path):
            note = "no patch" if not os.path.isfile(patch_file) else "no snapshot"
            print("{:<55} {} ({})".format(name, "N/A", note))
            results.append(dict(instance=name, pass_buggy='N/A', fail_buggy='N/A',
                                pass_patched='N/A', fail_patched='N/A', fail_to_pass='N/A', note=note))
            continue

        # Step 1: Run on buggy code (current original state)
        out_buggy = run_testbench(tb_path)
        pass_buggy, fail_buggy = count_pass_fail(out_buggy)

        # Step 2: Forward-apply patch
        if not do_patch(snap_path, patch_file):
            print("{:<55} {:>13} {:>12} {} (patch failed)".format(name, pass_buggy, fail_buggy, "N/A"))
            results.append(dict(instance=name, pass_buggy=pass_buggy, fail_buggy=fail_buggy,
                                pass_patched='N/A', fail_patched='N/A', fail_to_pass='N/A', note='patch failed'))
            continue

        # Step 3: Run on patched code
        out_patched = run_testbench(tb_path)
        pass_patched, fail_patched = count_pass_fail(out_patched)

        # Step 4: Restore to buggy state
        if not do_patch(snap_path, patch_file, reverse=True):
            sys.stderr.write("WARNING: Failed to restore {} to original state!\n".format(name))

        # Step 5: fail_to_pass
        f2p = pass_patched - pass_buggy
        if f2p < 0:
            f2p = 0

        print(fmt.format(name, pass_buggy, fail_buggy, pass_patched, fail_patched, f2p))
        results.append(dict(instance=name, pass_buggy=pass_buggy, fail_buggy=fail_buggy,
                            pass_patched=pass_patched, fail_patched=fail_patched,
                            fail_to_pass=f2p, note=''))

    # Write CSV
    csv_file = os.path.join(BASE_DIR, "fail_to_pass_results.csv")
    with open(csv_file, 'w') as f:
        writer = csv.DictWriter(f, fieldnames=['instance', 'pass_buggy', 'fail_buggy',
                                                'pass_patched', 'fail_patched', 'fail_to_pass', 'note'])
        writer.writeheader()
        for r in results:
            writer.writerow(r)

    # Summary
    print("\n" + "=" * 115)
    valid = [r for r in results if isinstance(r.get('fail_to_pass'), int)]
    total_f2p = sum(r['fail_to_pass'] for r in valid)
    print("Total testbenches: {}".format(len(results)))
    print("Successfully analyzed: {}".format(len(valid)))
    print("Total fail-to-pass test cases: {}".format(total_f2p))
    print("Average F2P per testbench: {:.1f}".format(total_f2p / len(valid) if valid else 0))
    print("Results saved to: {}".format(csv_file))


if __name__ == '__main__':
    main()

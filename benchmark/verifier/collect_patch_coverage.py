#!/usr/bin/env python3
"""
Collect coverage specifically around patched lines.
For each testbench:
  1. Parse patch to find modified files and line numbers (in patched version)
  2. Run TB on patched code with coverage
  3. Extract per-line coverage from urg report
  4. Report coverage for patch-adjacent lines (±context)
"""

import subprocess, os, re, csv, sys

BASE = "/workspace/phoenix-bench/HDL_verified_new"
TB_DIR = os.path.join(BASE, "testbench")
SNAP_DIR = os.path.join(BASE, "snapshots")
PATCH_DIR = os.path.join(BASE, "patches")
TIMEOUT = 120
CONTEXT = 5  # lines around patch to consider


def parse_patch(patch_file):
    """Parse a unified diff patch to get (file, set_of_new_line_numbers).
    Returns dict: {relative_file_path: set(line_numbers)} for added/changed lines."""
    result = {}
    current_file = None
    new_line = 0

    with open(patch_file, 'r', errors='replace') as f:
        for line in f:
            # Match "diff --git a/xxx b/xxx" or "+++ b/xxx"
            m = re.match(r'^\+\+\+ b/(.+)', line)
            if m:
                current_file = m.group(1).strip()
                if current_file not in result:
                    result[current_file] = set()
                continue

            # Match @@ hunk header: @@ -old,count +new,count @@
            m = re.match(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@', line)
            if m:
                new_line = int(m.group(1))
                continue

            if current_file is None:
                continue

            if line.startswith('+') and not line.startswith('+++'):
                result[current_file].add(new_line)
                new_line += 1
            elif line.startswith('-') and not line.startswith('---'):
                # Deleted line: the surrounding context in new file is relevant
                # Mark the current new_line position as relevant
                result[current_file].add(new_line)
                # Don't increment new_line for deleted lines
            else:
                new_line += 1

    return result


def expand_lines(line_set, context=CONTEXT):
    """Expand a set of line numbers with ±context."""
    expanded = set()
    for l in line_set:
        for c in range(max(1, l - context), l + context + 1):
            expanded.add(c)
    return expanded


def do_patch(snap, pf, reverse=False):
    cmd = ['patch', '-p1', '--batch', '--fuzz=3', '-i', pf]
    if reverse: cmd.insert(1, '-R')
    r = subprocess.run(cmd, cwd=snap, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    return r.returncode == 0


def run_tb(tb):
    log = os.path.join(tb, 'simv.log')
    if os.path.exists(log): os.remove(log)
    try:
        subprocess.run(['bash', 'run.sh'], cwd=tb,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=TIMEOUT)
    except:
        pass


def get_line_coverage_from_urg(tb, snap_name):
    """Run urg and parse per-line coverage. Returns dict: {basename: {line_no: (hit, total)}}."""
    vdb = os.path.join(tb, 'simv.vdb')
    if not os.path.isdir(vdb):
        return {}

    rpt = '/tmp/urg_patch_cov'
    subprocess.run(['rm', '-rf', rpt], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        subprocess.run(
            ['urg', '-dir', vdb, '-metric', 'line+cond', '-format', 'text', '-report', rpt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    except:
        return {}

    modinfo = os.path.join(rpt, 'modinfo.txt')
    if not os.path.exists(modinfo):
        return {}

    coverage = {}  # {basename: {line_no: (hit, total)}}

    with open(modinfo, errors='replace') as f:
        txt = f.read()

    # Split by module sections and find source files + line coverage
    current_basename = None
    for line in txt.split('\n'):
        line_s = line.strip()

        # Detect source file path
        if line_s.endswith('.sv') and ('/' in line_s or '\\' in line_s):
            bname = os.path.basename(line_s)
            current_basename = bname
            if bname not in coverage:
                coverage[bname] = {}
            continue

        # Detect "Line Coverage for Module" section reset
        if 'Line Coverage for Module' in line:
            # Keep current_basename as set by source file
            continue

        # Parse line coverage: "51         0/1" or "50         1/1"
        if current_basename:
            m = re.match(r'^\s*(\d+)\s+(\d+)/(\d+)', line)
            if m:
                lineno = int(m.group(1))
                hit = int(m.group(2))
                total = int(m.group(3))
                coverage[current_basename][lineno] = (hit, total)

    return coverage


def main():
    tb_names = sorted(os.listdir(TB_DIR))
    results = []

    fmt = "{:<55} {:>8} {:>8} {:>8} {:>10}"
    print(fmt.format("Instance", "PatchLn", "Covered", "Total", "PatchCov%"))
    print("-" * 95)

    for name in tb_names:
        tb = os.path.join(TB_DIR, name)
        if not os.path.isdir(tb):
            continue

        snap = os.path.join(SNAP_DIR, name)
        pf = os.path.join(PATCH_DIR, "{}.patch".format(name))

        if not os.path.isfile(pf) or not os.path.isdir(snap):
            print(fmt.format(name, 'N/A', 'N/A', 'N/A', 'N/A'))
            results.append({'instance': name, 'patch_lines': '', 'covered': '', 'total': '', 'patch_cov': '', 'note': 'missing'})
            continue

        # Step 1: Parse patch
        patch_files = parse_patch(pf)
        if not patch_files:
            print(fmt.format(name, '0', 'N/A', 'N/A', 'N/A'))
            results.append({'instance': name, 'patch_lines': '0', 'covered': '', 'total': '', 'patch_cov': '', 'note': 'no code changes'})
            continue

        # Expand to include context lines
        patch_lines_expanded = {f: expand_lines(lines) for f, lines in patch_files.items()}
        total_patch_lines = sum(len(v) for v in patch_files.values())

        # Step 2: Apply patch and run
        patched = do_patch(snap, pf)
        if not patched:
            print(fmt.format(name, str(total_patch_lines), 'N/A', 'N/A', 'N/A (patch fail)'))
            results.append({'instance': name, 'patch_lines': str(total_patch_lines), 'covered': '', 'total': '', 'patch_cov': '', 'note': 'patch failed'})
            continue

        run_tb(tb)

        # Step 3: Extract coverage
        cov_data = get_line_coverage_from_urg(tb, name)

        # Step 4: Match patch lines with coverage using basename matching
        covered_count = 0
        coverable_count = 0

        for fpath, line_set in patch_lines_expanded.items():
            bname = os.path.basename(fpath)
            if bname in cov_data:
                for ln in sorted(line_set):
                    if ln in cov_data[bname]:
                        coverable_count += 1
                        hit, total = cov_data[bname][ln]
                        if hit > 0:
                            covered_count += 1

        # Also check with just the patch lines (no context)
        covered_exact = 0
        coverable_exact = 0
        for fpath, line_set in patch_files.items():
            bname = os.path.basename(fpath)
            if bname in cov_data:
                for ln in sorted(line_set):
                    if ln in cov_data[bname]:
                        coverable_exact += 1
                        hit, total = cov_data[bname][ln]
                        if hit > 0:
                            covered_exact += 1

        # Step 5: Restore
        do_patch(snap, pf, reverse=True)

        if coverable_count > 0:
            pct = 100.0 * covered_count / coverable_count
            pct_str = "{:.1f}%".format(pct)
        elif coverable_exact > 0:
            pct = 100.0 * covered_exact / coverable_exact
            pct_str = "{:.1f}%".format(pct)
        elif not cov_data:
            pct_str = "no cm"
            pct = ''
        else:
            pct_str = "0 cov"
            pct = ''

        if coverable_count > 0:
            print(fmt.format(name, str(total_patch_lines), str(covered_count), str(coverable_count), pct_str))
        else:
            print(fmt.format(name, str(total_patch_lines), str(covered_exact), str(coverable_exact), pct_str))

        results.append({
            'instance': name,
            'patch_lines': str(total_patch_lines),
            'covered': str(covered_count if coverable_count > 0 else covered_exact),
            'total': str(coverable_count if coverable_count > 0 else coverable_exact),
            'patch_cov': str(pct) if isinstance(pct, float) else '',
            'note': pct_str if not isinstance(pct, float) else ''
        })

    # Write CSV
    csv_file = os.path.join(BASE, "patch_coverage_results.csv")
    with open(csv_file, 'w') as f:
        w = csv.DictWriter(f, fieldnames=['instance', 'patch_lines', 'covered', 'total', 'patch_cov', 'note'])
        w.writeheader()
        w.writerows(results)

    # Summary
    print("\n" + "=" * 95)
    valid = [float(r['patch_cov']) for r in results if r['patch_cov'] and r['patch_cov'] not in ('', 'N/A')]
    if valid:
        print("Testbenches with patch-area coverage: {}/{}".format(len(valid), len(results)))
        print("Min:    {:.1f}%".format(min(valid)))
        print("Max:    {:.1f}%".format(max(valid)))
        print("Avg:    {:.1f}%".format(sum(valid) / len(valid)))
        s = sorted(valid)
        print("Median: {:.1f}%".format(s[len(s) // 2]))
    print("\nResults saved to: {}".format(csv_file))


if __name__ == '__main__':
    main()

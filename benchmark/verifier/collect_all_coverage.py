#!/usr/bin/env python3
"""Collect all coverage metrics (line, cond, toggle, fsm, branch, group/functional)
for each testbench on patched code."""

import subprocess, os, re, csv

BASE = "/workspace/phoenix-bench/HDL_verified_new"
TB_DIR = os.path.join(BASE, "testbench")
SNAP_DIR = os.path.join(BASE, "snapshots")
PATCH_DIR = os.path.join(BASE, "patches")
TIMEOUT = 120

def do_patch(snap, pf, reverse=False):
    cmd = ['patch', '-p1', '--batch', '--fuzz=3', '-i', pf]
    if reverse: cmd.insert(1, '-R')
    r = subprocess.run(cmd, cwd=snap, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
    return r.returncode == 0

def run_tb(tb):
    log = os.path.join(tb, 'simv.log')
    if os.path.exists(log): os.remove(log)
    try:
        r = subprocess.run(['bash','run.sh'], cwd=tb, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=TIMEOUT)
        out = r.stdout.decode('utf-8', errors='replace') + '\n' + r.stderr.decode('utf-8', errors='replace')
    except:
        out = ''
    # Also read simv.log
    if os.path.exists(log):
        try:
            r2 = subprocess.run(['strings', log], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10)
            out += '\n' + r2.stdout.decode('utf-8', errors='replace')
        except: pass
    return out

def get_func_cov(out):
    m = re.findall(r'[Ff]unctional [Cc]overage[:\s=]+([0-9.]+)%', out)
    return m[-1] if m else ''

def get_urg_coverage(tb):
    """Run urg and parse code coverage metrics."""
    vdb = os.path.join(tb, 'simv.vdb')
    if not os.path.isdir(vdb):
        return {}
    rpt = '/tmp/urg_cov_tmp'
    try:
        r = subprocess.run(
            ['urg', '-dir', vdb, '-metric', 'line+cond+tgl+branch+fsm+group',
             '-format', 'text', '-report', rpt],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30)
        dash = os.path.join(rpt, 'dashboard.txt')
        if not os.path.exists(dash):
            return {}
        with open(dash) as f:
            txt = f.read()
        # Parse "SCORE  LINE   COND   TOGGLE FSM    BRANCH GROUP" line
        m = re.search(r'Total Coverage Summary\s+SCORE\s+(.+?)\n\s*([0-9.\-\s]+)', txt)
        if not m:
            return {}
        headers = m.group(1).split()
        values = m.group(2).split()
        result = {}
        for h, v in zip(headers, values):
            h = h.strip().lower()
            if v == '--':
                result[h] = '--'
            else:
                try: result[h] = float(v)
                except: result[h] = v
        return result
    except:
        return {}
    finally:
        subprocess.run(['rm', '-rf', rpt], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def main():
    tb_names = sorted(os.listdir(TB_DIR))
    results = []

    hdr = "{:<50} {:>6} {:>6} {:>6} {:>6} {:>6} {:>6} {:>6}".format(
        "Instance", "Line", "Cond", "Toggle", "FSM", "Branch", "FuncCov", "Score")
    print(hdr)
    print("-" * len(hdr))

    for name in tb_names:
        tb = os.path.join(TB_DIR, name)
        if not os.path.isdir(tb): continue
        snap = os.path.join(SNAP_DIR, name)
        pf = os.path.join(PATCH_DIR, "{}.patch".format(name))

        row = {'instance': name, 'line': '', 'cond': '', 'toggle': '', 'fsm': '', 'branch': '', 'func': '', 'score': ''}

        # Apply patch
        patched = False
        if os.path.isfile(pf) and os.path.isdir(snap):
            patched = do_patch(snap, pf)

        # Run TB
        out = run_tb(tb)
        row['func'] = get_func_cov(out)

        # Get code coverage via urg
        cov = get_urg_coverage(tb)
        for k in ['line', 'cond', 'toggle', 'fsm', 'branch']:
            if k in cov:
                row[k] = str(cov[k]) if cov[k] != '--' else '--'
        if 'group' in cov:
            if not row['func'] and cov['group'] != '--':
                row['func'] = str(cov['group'])
        # Score from urg
        m = re.search(r'Total Coverage Summary\s+SCORE.*?\n\s*([0-9.]+)', open('/tmp/urg_cov_tmp/dashboard.txt').read()) if os.path.exists('/tmp/urg_cov_tmp/dashboard.txt') else None
        if cov:
            # compute score from values
            vals = [v for k,v in cov.items() if k != 'group' and isinstance(v, float)]
            if vals:
                row['score'] = "{:.1f}".format(sum(vals)/len(vals))

        # Restore
        if patched:
            do_patch(snap, pf, reverse=True)

        def fmt(v):
            if v == '' or v is None: return 'N/A'
            if v == '--': return '--'
            try: return "{:.1f}".format(float(v))
            except: return str(v)

        print("{:<50} {:>6} {:>6} {:>6} {:>6} {:>6} {:>6} {:>6}".format(
            name, fmt(row['line']), fmt(row['cond']), fmt(row['toggle']),
            fmt(row['fsm']), fmt(row['branch']), fmt(row['func']), fmt(row['score'])))
        results.append(row)

    # Write CSV
    csv_file = os.path.join(BASE, "all_coverage_results.csv")
    with open(csv_file, 'w') as f:
        w = csv.DictWriter(f, fieldnames=['instance','line','cond','toggle','fsm','branch','func','score'])
        w.writeheader()
        w.writerows(results)

    # Summary stats
    print("\n" + "=" * 100)
    for metric in ['line', 'cond', 'toggle', 'fsm', 'branch', 'func']:
        vals = [float(r[metric]) for r in results if r[metric] not in ('', '--', 'N/A', None)]
        if vals:
            print("{:<10} count={:<3} min={:>6.1f}%  max={:>6.1f}%  avg={:>6.1f}%  median={:>6.1f}%".format(
                metric, len(vals), min(vals), max(vals), sum(vals)/len(vals),
                sorted(vals)[len(vals)//2]))
    print("\nResults saved to: {}".format(csv_file))

if __name__ == '__main__':
    main()

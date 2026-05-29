#!/usr/bin/env python3
"""aggregate_closing_issues.py

Read a JSON file containing PR items (like the example you provided) and
extract all `closing_issues` entries into aggregated JSON / CSV / Markdown files.

Default input path: /workspace/phoenix-bench/condidates.json
Outputs (in the same directory as input):
 - closing_issues_aggregated.json
 - closing_issues_aggregated.csv
 - closing_issues_aggregated.md

Usage:
  python3 aggregate_closing_issues.py --input /path/to/condidates.json

The script is defensive: it accepts either a top-level list of items or a dict.
"""

import argparse
import json
import os
import csv
from typing import List, Dict, Any


def load_items(path: str) -> List[Dict[str, Any]]:
    with open(path, 'r', encoding='utf-8') as f:
        data = json.load(f)
    # If file is a list of items, return directly
    if isinstance(data, list):
        return data
    # If it's a dict with an obvious list inside, try common keys
    if isinstance(data, dict):
        # common candidates
        for key in ("items", "prs", "candidates", "repos", "data", "results"):
            if key in data and isinstance(data[key], list):
                return data[key]
        # fallback: if values contain list-like items with 'repo' or 'pr_number'
        for v in data.values():
            if isinstance(v, list) and v and isinstance(v[0], dict) and ('repo' in v[0] or 'pr_number' in v[0]):
                return v
        # last resort: wrap the dict itself
        return [data]
    raise ValueError("Unsupported JSON structure: top-level is neither list nor dict")


def aggregate_closing_issues(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    seen = set()
    aggregated = []
    for item in items:
        repo = item.get('repo') or item.get('repository')
        pr_number = item.get('pr_number')
        pr_title = item.get('pr_title')
        pr_url = item.get('pr_url')
        merged_at = item.get('merged_at')
        author = item.get('author')
        closing = item.get('closing_issues') or []
        if not isinstance(closing, list):
            # sometimes it may be a dict or None
            continue
        for issue in closing:
            # expected: number, title, url (based on example)
            num = issue.get('number')
            title = issue.get('title')
            url = issue.get('url')
            key = url or f"{repo}#{num}" if repo and num is not None else f"{repo}-{num}-{title}"
            if key in seen:
                continue
            seen.add(key)
            aggregated.append({
                'repo': repo,
                'pr_number': pr_number,
                'pr_title': pr_title,
                'pr_url': pr_url,
                'merged_at': merged_at,
                'pr_author': author,
                'issue_number': num,
                'issue_title': title,
                'issue_url': url
            })
    return aggregated


def write_outputs(aggregated: List[Dict[str, Any]], out_dir: str):
    os.makedirs(out_dir, exist_ok=True)
    json_path = os.path.join(out_dir, 'closing_issues_aggregated.json')
    csv_path = os.path.join(out_dir, 'closing_issues_aggregated.csv')
    md_path = os.path.join(out_dir, 'closing_issues_aggregated.md')

    # JSON
    with open(json_path, 'w', encoding='utf-8') as f:
        json.dump(aggregated, f, ensure_ascii=False, indent=2)

    # CSV
    fieldnames = ['repo', 'pr_number', 'pr_title', 'pr_url', 'merged_at', 'pr_author', 'issue_number', 'issue_title', 'issue_url']
    with open(csv_path, 'w', newline='', encoding='utf-8') as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        for row in aggregated:
            writer.writerow({k: ('' if row.get(k) is None else row.get(k)) for k in fieldnames})

    # Markdown table (simple)
    with open(md_path, 'w', encoding='utf-8') as f:
        f.write('| repo | pr_number | issue_number | issue_title | issue_url |\n')
        f.write('|---|---:|---:|---|---|\n')
        for row in aggregated:
            repo = row.get('repo') or ''
            prn = row.get('pr_number') or ''
            inn = row.get('issue_number') or ''
            title = (row.get('issue_title') or '').replace('|', '\\|')
            url = row.get('issue_url') or ''
            f.write(f'| {repo} | {prn} | {inn} | {title} | {url} |\n')

    return json_path, csv_path, md_path


def main():
    p = argparse.ArgumentParser(description='Aggregate closing_issues from a JSON of PR items')
    p.add_argument('--input', '-i', default='/workspace/phoenix-bench/condidates.json', help='input JSON file path')
    p.add_argument('--outdir', '-o', default=None, help='output directory (defaults to input file dir)')
    args = p.parse_args()

    if not os.path.exists(args.input):
        print(f'Input file not found: {args.input}', flush=True)
        raise SystemExit(1)

    items = load_items(args.input)
    aggregated = aggregate_closing_issues(items)
    outdir = args.outdir if args.outdir else os.path.dirname(os.path.abspath(args.input))
    json_path, csv_path, md_path = write_outputs(aggregated, outdir)

    print(f'Aggregated {len(aggregated)} unique closing issues.')
    print('Wrote:')
    print('  ', json_path)
    print('  ', csv_path)
    print('  ', md_path)


if __name__ == '__main__':
    main()

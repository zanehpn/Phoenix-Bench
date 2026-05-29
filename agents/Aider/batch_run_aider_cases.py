#!/usr/bin/env python3

import argparse
import csv
import json
import os
import subprocess
import sys
import time
from datetime import datetime
from typing import Dict, List, Optional, Set


ISSUES_DIR = "/workspace/phoenix-bench/HDL_verified_new/issues"
SNAPSHOTS_DIR = "/workspace/phoenix-bench/HDL_verified_new/snapshots"
TESTBENCH_DIR = "/workspace/phoenix-bench/HDL_verified_new/testbench"
PATCHES_DIR = "/workspace/phoenix-bench/HDL_verified_new/patches"
RUN_CASE_SCRIPT = "/workspace/phoenix-bench/aider_test/run_aider_case.py"
OUT_ROOT = "/workspace/phoenix-bench/aider_test"


def ensure_dir(path: str) -> None:
    os.makedirs(path, exist_ok=True)


def read_json(path: str) -> Dict[str, object]:
    with open(path, "r", encoding="utf-8") as f:
        obj = json.load(f)
    if not isinstance(obj, dict):
        raise RuntimeError(f"invalid json object: {path}")
    return obj


def tail(text: str, lines: int = 20) -> str:
    parts = [line.rstrip() for line in text.splitlines() if line.strip()]
    return "\n".join(parts[-lines:]) if parts else ""


def parse_names_arg(names: str) -> Optional[Set[str]]:
    out = {x.strip() for x in names.split(",") if x.strip()}
    return out or None


def discover_cases() -> List[str]:
    issues = {f for f in os.listdir(ISSUES_DIR) if os.path.isfile(os.path.join(ISSUES_DIR, f))}
    snaps = {d for d in os.listdir(SNAPSHOTS_DIR) if os.path.isdir(os.path.join(SNAPSHOTS_DIR, d))}
    testbench = {d for d in os.listdir(TESTBENCH_DIR) if os.path.isdir(os.path.join(TESTBENCH_DIR, d))}
    patches = {p[:-6] for p in os.listdir(PATCHES_DIR) if p.endswith(".patch")}
    return sorted(issues & snaps & testbench & patches)


def read_patch_files(patch_path: str) -> List[str]:
    out: List[str] = []
    if not os.path.isfile(patch_path):
        return out
    with open(patch_path, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            if line.startswith("+++ b/"):
                rel = line[6:].strip()
                if rel and rel != "/dev/null" and rel not in out:
                    out.append(rel)
    return out


def ratio(num: int, den: int) -> float:
    return float(num) / float(den) if den else 0.0


def f1(precision: float, recall: float) -> float:
    if precision <= 0.0 or recall <= 0.0:
        return 0.0
    return 2.0 * precision * recall / (precision + recall)


def list_run_dirs(case_name: str) -> Set[str]:
    runs_root = os.path.join(OUT_ROOT, case_name, "runs")
    if not os.path.isdir(runs_root):
        return set()
    return {
        os.path.join(runs_root, name)
        for name in os.listdir(runs_root)
        if os.path.isdir(os.path.join(runs_root, name))
    }


def find_new_run_dir(before: Set[str], case_name: str) -> str:
    after = list_run_dirs(case_name)
    created = sorted(after - before)
    if created:
        return created[-1]
    if after:
        return sorted(after)[-1]
    raise RuntimeError(f"no run directory found for case {case_name}")


def run_one_case(case_name: str, args: argparse.Namespace, batch_dir: str) -> Dict[str, object]:
    before = list_run_dirs(case_name)
    cmd = [
        sys.executable,
        RUN_CASE_SCRIPT,
        "--case",
        case_name,
        "--model",
        args.model,
        "--api-base",
        args.api_base,
    ]
    t0 = time.time()
    proc = subprocess.run(
        cmd,
        cwd=args.workdir,
        capture_output=True,
        text=True,
        timeout=args.case_timeout_sec,
    )
    duration = round(time.time() - t0, 3)
    run_dir = find_new_run_dir(before, case_name)
    status_path = os.path.join(run_dir, "status.json")
    status = read_json(status_path) if os.path.isfile(status_path) else {}

    gt_files = read_patch_files(os.path.join(PATCHES_DIR, f"{case_name}.patch"))
    gt_set = set(gt_files)
    pred_files = status.get("touched_files") or []
    pred_set = {x for x in pred_files if isinstance(x, str)}
    hits = sorted(gt_set & pred_set)
    precision = ratio(len(hits), len(pred_set))
    recall = ratio(len(hits), len(gt_set))

    record: Dict[str, object] = {
        "name": case_name,
        "duration_sec": duration,
        "returncode": proc.returncode,
        "run_dir": run_dir,
        "status_json": status_path,
        "stdout_tail": tail(proc.stdout),
        "stderr_tail": tail(proc.stderr),
        "llm_status": status.get("final_status", ""),
        "actual_test_status": status.get("final_actual_status", ""),
        "attempt_count": len(status.get("attempts", [])) if isinstance(status.get("attempts"), list) else 0,
        "final_patch": status.get("final_patch", ""),
        "gt_files": sorted(gt_set),
        "pred_files": sorted(pred_set),
        "gt_file_count": len(gt_set),
        "pred_file_count": len(pred_set),
        "hit_file_count": len(hits),
        "file_precision": round(precision, 4),
        "file_recall": round(recall, 4),
        "file_f1": round(f1(precision, recall), 4),
        "file_exact_match": gt_set == pred_set,
    }
    per_case_json = os.path.join(batch_dir, "cases", f"{case_name}.json")
    ensure_dir(os.path.dirname(per_case_json))
    with open(per_case_json, "w", encoding="utf-8") as f:
        json.dump(record, f, ensure_ascii=False, indent=2)
    return record


def summarize(records: List[Dict[str, object]]) -> Dict[str, object]:
    total = len(records)
    actual_pass = [r for r in records if r.get("actual_test_status") == "pass"]
    llm_pass = [r for r in records if r.get("llm_status") == "pass"]
    exact = [r for r in records if bool(r.get("file_exact_match"))]

    def avg(key: str) -> float:
        if not records:
            return 0.0
        return round(sum(float(r.get(key, 0.0)) for r in records) / len(records), 4)

    return {
        "total_cases": total,
        "actual_pass_cases": len(actual_pass),
        "actual_pass_rate": round(ratio(len(actual_pass), total), 4) if total else 0.0,
        "reported_pass_cases": len(llm_pass),
        "reported_pass_rate": round(ratio(len(llm_pass), total), 4) if total else 0.0,
        "file_exact_match_cases": len(exact),
        "file_accuracy": round(ratio(len(exact), total), 4) if total else 0.0,
        "avg_file_precision": avg("file_precision"),
        "avg_file_recall": avg("file_recall"),
        "avg_file_f1": avg("file_f1"),
        "failed_actual_test_cases": [r["name"] for r in records if r.get("actual_test_status") != "pass"],
    }


def write_csv(records: List[Dict[str, object]], path: str) -> None:
    fields = [
        "name",
        "duration_sec",
        "returncode",
        "attempt_count",
        "actual_test_status",
        "llm_status",
        "gt_file_count",
        "pred_file_count",
        "hit_file_count",
        "file_precision",
        "file_recall",
        "file_f1",
        "file_exact_match",
        "run_dir",
        "final_patch",
        "status_json",
        "stderr_tail",
    ]
    with open(path, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        for record in records:
            writer.writerow({field: record.get(field, "") for field in fields})


def main() -> None:
    ap = argparse.ArgumentParser(description="Batch run isolated aider HDL fixes and compute file accuracy.")
    ap.add_argument("--workdir", default="/workspace/phoenix-bench")
    ap.add_argument("--model", default="gpt-5.2")
    ap.add_argument("--api-base", default="https://api.openai.com/v1")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--names", default="")
    ap.add_argument("--case-timeout-sec", type=int, default=5400)
    args = ap.parse_args()

    batch_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    batch_dir = os.path.join(OUT_ROOT, "batch_runs", batch_id)
    ensure_dir(batch_dir)

    cases = discover_cases()
    selected = parse_names_arg(args.names)
    if selected is not None:
        cases = [case for case in cases if case in selected]
    if args.limit > 0:
        cases = cases[:args.limit]
    if not cases:
        raise SystemExit("no matching cases found")

    config = {
        "batch_id": batch_id,
        "case_count": len(cases),
        "model": args.model,
        "api_base": args.api_base,
        "case_timeout_sec": args.case_timeout_sec,
        "cases": cases,
    }
    with open(os.path.join(batch_dir, "config.json"), "w", encoding="utf-8") as f:
        json.dump(config, f, ensure_ascii=False, indent=2)

    print(json.dumps({"batch_dir": batch_dir, "total_cases": len(cases)}, ensure_ascii=False))
    sys.stdout.flush()

    records: List[Dict[str, object]] = []
    for idx, case_name in enumerate(cases, start=1):
        print(f"[{idx}/{len(cases)}] {case_name}")
        sys.stdout.flush()
        try:
            record = run_one_case(case_name, args, batch_dir)
        except subprocess.TimeoutExpired:
            record = {
                "name": case_name,
                "duration_sec": float(args.case_timeout_sec),
                "returncode": -999,
                "run_dir": "",
                "status_json": "",
                "stdout_tail": "",
                "stderr_tail": f"timeout after {args.case_timeout_sec}s",
                "llm_status": "timeout",
                "actual_test_status": "timeout",
                "attempt_count": 0,
                "final_patch": "",
                "gt_files": read_patch_files(os.path.join(PATCHES_DIR, f"{case_name}.patch")),
                "pred_files": [],
                "gt_file_count": 0,
                "pred_file_count": 0,
                "hit_file_count": 0,
                "file_precision": 0.0,
                "file_recall": 0.0,
                "file_f1": 0.0,
                "file_exact_match": False,
            }
        except Exception as exc:
            record = {
                "name": case_name,
                "duration_sec": 0.0,
                "returncode": -998,
                "run_dir": "",
                "status_json": "",
                "stdout_tail": "",
                "stderr_tail": f"runner exception: {exc}",
                "llm_status": "error",
                "actual_test_status": "error",
                "attempt_count": 0,
                "final_patch": "",
                "gt_files": read_patch_files(os.path.join(PATCHES_DIR, f"{case_name}.patch")),
                "pred_files": [],
                "gt_file_count": 0,
                "pred_file_count": 0,
                "hit_file_count": 0,
                "file_precision": 0.0,
                "file_recall": 0.0,
                "file_f1": 0.0,
                "file_exact_match": False,
            }

        if int(record.get("gt_file_count", 0)) == 0:
            gt_files = record.get("gt_files", [])
            if isinstance(gt_files, list):
                record["gt_file_count"] = len(gt_files)
        records.append(record)

        with open(os.path.join(batch_dir, "progress.json"), "w", encoding="utf-8") as f:
            json.dump(
                {
                    "completed_cases": len(records),
                    "total_cases": len(cases),
                    "latest_case": case_name,
                    "summary_so_far": summarize(records),
                },
                f,
                ensure_ascii=False,
                indent=2,
            )
        print(
            json.dumps(
                {
                    "case": case_name,
                    "actual_test_status": record.get("actual_test_status"),
                    "file_exact_match": record.get("file_exact_match"),
                    "run_dir": record.get("run_dir"),
                },
                ensure_ascii=False,
            )
        )
        sys.stdout.flush()

    summary = summarize(records)
    payload = {"config": config, "summary": summary, "records": records}
    summary_json = os.path.join(batch_dir, "summary.json")
    summary_csv = os.path.join(batch_dir, "summary.csv")
    with open(summary_json, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)
    write_csv(records, summary_csv)

    print(json.dumps({"summary_json": summary_json, "summary_csv": summary_csv, "summary": summary}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()

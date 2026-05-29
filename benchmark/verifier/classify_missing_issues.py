"""
Classify the issues that are present in `issues/` but absent from
`classified_issues_new.jsonl`, by reusing the prompt/LLM logic in
/workspace/phoenix-bench-analysis/llm_divide_issue.py.

For each missing case:
  - read the body from issues/<case_name>
  - build a minimal issue dict
  - call the same LLM-based classifier used originally
  - append the classified entry to classified_issues_new.jsonl
"""
import os
import sys
import json
import time

# Reuse the original script's helpers.
sys.path.insert(0, "/workspace/phoenix-bench-analysis")
from llm_divide_issue import (  # type: ignore
    BIG_CATEGORIES,
    SUBCATEGORIES,
    build_prompt,
    deepseek_v3,
    safe_json_parse,
)

ROOT = "/workspace/phoenix-bench/HDL_verified_new"
ISSUES_DIR = os.path.join(ROOT, "issues")
OUT_PATH = os.path.join(ROOT, "classified_issues_new.jsonl")
PROGRESS_PATH = os.path.join(ROOT, "classify_missing_progress.json")


def case_to_repo_and_number(case_name: str):
    """`AUCOHL_Lighter_pr16` -> ('AUCOHL/Lighter', 16).
    Splits at the LAST `_pr` so repo names with `_pr` substrings stay intact."""
    idx = case_name.rfind("_pr")
    if idx == -1:
        return case_name, None
    repo_part = case_name[:idx]
    num_part = case_name[idx + 3 :]
    try:
        num = int(num_part)
    except ValueError:
        num = None
    org, _, rest = repo_part.partition("_")
    repo = f"{org}/{rest}" if rest else org
    return repo, num


def load_done_case_names(path: str):
    done = set()
    if not os.path.exists(path):
        return done
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                cn = obj.get("case_name")
                if cn:
                    done.add(cn)
            except Exception:
                pass
    return done


def main():
    done = load_done_case_names(OUT_PATH)
    all_cases = {
        name
        for name in os.listdir(ISSUES_DIR)
        if os.path.isfile(os.path.join(ISSUES_DIR, name))
    }
    missing = sorted(all_cases - done)
    print(f"issues dir cases: {len(all_cases)}")
    print(f"already classified case_names: {len(done)}")
    print(f"missing to classify: {len(missing)}")

    if not missing:
        return

    out_f = open(OUT_PATH, "a", encoding="utf-8")

    try:
        for i, case_name in enumerate(missing, 1):
            issue_path = os.path.join(ISSUES_DIR, case_name)
            with open(issue_path, "r", encoding="utf-8", errors="ignore") as f:
                body = f.read().strip()

            repo, issue_number = case_to_repo_and_number(case_name)

            # Use the first non-empty line as a synthetic title.
            first_line = next(
                (ln.strip() for ln in body.splitlines() if ln.strip()), ""
            )
            title = first_line[:200] if first_line else case_name

            issue = {
                "case_name": case_name,
                "repo": repo,
                "issue_number": issue_number,
                "issue_title": title,
                "html_url": "",
                "body": body,
            }

            prompt = build_prompt(issue)
            raw = deepseek_v3(prompt)
            parsed = safe_json_parse(raw)

            if (not parsed) or (parsed.get("category") not in BIG_CATEGORIES):
                fallback_cat = BIG_CATEGORIES[0]
                fallback_sub = list(SUBCATEGORIES[fallback_cat].keys())[0]
                parsed = {
                    "category": fallback_cat,
                    "subcategory": fallback_sub,
                    "confidence": 0.0,
                    "reason": f"Unparseable output, forced fallback. raw={str(raw)[:160]}",
                }

            cat = parsed["category"]
            sub = parsed.get("subcategory")
            valid_subs = list(SUBCATEGORIES.get(cat, {}).keys())
            if sub not in valid_subs:
                sub = valid_subs[0] if valid_subs else None

            result = {
                "case_name": case_name,
                "repo": repo,
                "issue_number": issue_number,
                "issue_title": title,
                "html_url": "",
                "category": cat,
                "subcategory": sub,
                "confidence": float(parsed.get("confidence", 0.5)),
                "category_reason": parsed.get("reason", ""),
            }

            out_f.write(json.dumps(result, ensure_ascii=False) + "\n")
            out_f.flush()
            print(f"[{i}/{len(missing)}] {case_name} -> {cat} | {sub}")
            time.sleep(0.2)
    finally:
        out_f.close()

    print("Done.")


if __name__ == "__main__":
    main()

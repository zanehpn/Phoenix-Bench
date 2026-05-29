#!/usr/bin/env python3
"""
fetch_repos.py
- 使用 GitHub Search API 搜索: language:Verilog created:>2022-01-01 stars:>=100
- 输出 repos.json，且可选择 --clone 将仓库 shallow clone 到 ./repos/
"""
import os
import requests
import time
import argparse
import subprocess
import json
from urllib.parse import quote_plus

GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")
if not GITHUB_TOKEN:
    raise SystemExit("请先在环境变量中设置 GITHUB_TOKEN")

HEADERS = {"Authorization": f"token {GITHUB_TOKEN}", "Accept": "application/vnd.github.v3+json"}
SEARCH_URL = "https://api.github.com/search/repositories"

def search_repos(q, per_page=30, max_pages=5):
    repos = []
    for page in range(1, max_pages+1):
        params = {"q": q, "per_page": per_page, "page": page}
        r = requests.get(SEARCH_URL, headers=HEADERS, params=params)
        if r.status_code != 200:
            print("Search API error", r.status_code, r.text)
            break
        data = r.json()
        items = data.get("items", [])
        repos.extend(items)
        if "next" not in r.links:
            break
        time.sleep(1)  # polite
    return repos

def clone_repo(clone_url, dest_dir):
    os.makedirs(dest_dir, exist_ok=True)
    repo_name = clone_url.split("/")[-1].replace(".git", "")
    target = os.path.join(dest_dir, repo_name)
    if os.path.exists(target):
        print("already cloned:", target)
        return target
    cmd = ["git", "clone", "--depth", "1", clone_url, target]
    print("Cloning:", clone_url)
    subprocess.check_call(cmd)
    return target

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--min-stars", type=int, default=50)
    parser.add_argument("--created-after", type=str, default="2022-01-01")
    parser.add_argument("--clone", action="store_true")
    parser.add_argument("--out", default="repos.json")
    args = parser.parse_args()

    q = f"language:Systemverilog stars:>={args.min_stars} created:>{args.created_after}"
    print("Query:", q)
    repos = search_repos(q, per_page=500, max_pages=500)
    print("Found repos:", len(repos))

    simplified = []
    for r in repos:
        info = {
            "full_name": r["full_name"],
            "html_url": r["html_url"],
            "clone_url": r["clone_url"],
            "stargazers_count": r["stargazers_count"],
            "language": r.get("language"),
            "created_at": r["created_at"],
            "description": r.get("description"),
        }
        simplified.append(info)
        if args.clone:
            try:
                clone_repo(r["clone_url"], "./repos")
            except Exception as e:
                print("clone failed", r["full_name"], e)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(simplified, f, indent=2, ensure_ascii=False)
    print("Wrote", args.out)

if __name__ == "__main__":
    main()

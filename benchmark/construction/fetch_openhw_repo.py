#!/usr/bin/env python3
"""
fetch_repos.py (final)
- Search GitHub for repos by language & stars (no created: filter)
- Also list repos under openhwgroup and lowRISC orgs (and fetch explicit lowRISC/fpga-zynq)
- Apply BOTH: star threshold AND language heuristic to decide inclusion
- Output repos.json; optional --clone shallow-clones matching repos into ./repos/
"""
import os
import requests
import time
import argparse
import subprocess
import json

GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")
if not GITHUB_TOKEN:
    raise SystemExit("请先在环境变量中设置 GITHUB_TOKEN")

HEADERS = {
    "Authorization": f"token {GITHUB_TOKEN}",
    "Accept": "application/vnd.github.v3+json"
}
SEARCH_URL = "https://api.github.com/search/repositories"
REST_BASE = "https://api.github.com"

# organizations and explicit repos to gather (we will still filter them by stars & language)
ORG_LIST = ["lowRISC", "openhwgroup"]
EXPLICIT_REPOS = ["lowRISC/fpga-zynq"]

# allowed languages (primary language field) we consider HDL
ALLOWED_LANGS = {"systemverilog", "verilog"}

def search_repos(query, per_page=30, max_pages=5):
    repos = []
    for page in range(1, max_pages + 1):
        params = {"q": query, "per_page": per_page, "page": page, "sort": "stars", "order": "desc"}
        r = requests.get(SEARCH_URL, headers=HEADERS, params=params)
        if r.status_code != 200:
            print("Search API error", r.status_code, r.text)
            break
        data = r.json()
        items = data.get("items", [])
        repos.extend(items)
        if "next" not in r.links:
            break
        time.sleep(1.0)
    return repos

def list_org_repos(org, per_page=100, max_pages=10):
    repos = []
    for page in range(1, max_pages + 1):
        url = f"{REST_BASE}/orgs/{org}/repos"
        params = {"per_page": per_page, "page": page, "type": "public", "sort": "updated"}
        r = requests.get(url, headers=HEADERS, params=params)
        if r.status_code == 404:
            print(f"Org not found or inaccessible: {org}")
            break
        if r.status_code != 200:
            print(f"Error listing org repos for {org}: {r.status_code} {r.text}")
            break
        data = r.json()
        if not data:
            break
        repos.extend(data)
        if "next" not in r.links:
            break
        time.sleep(0.8)
    return repos

def get_repo(full_name):
    url = f"{REST_BASE}/repos/{full_name}"
    r = requests.get(url, headers=HEADERS)
    if r.status_code == 200:
        return r.json()
    else:
        print(f"Warning: failed to fetch repo {full_name}: {r.status_code}")
        return None

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

def repo_matches_language(repo):
    """Return True if repo's primary language or hints look like Verilog/SystemVerilog."""
    lang = (repo.get("language") or "").lower()
    if lang in ALLOWED_LANGS:
        return True
    # try topics if available
    topics = repo.get("topics") or []
    if isinstance(topics, list) and any(t.lower() in ALLOWED_LANGS for t in topics):
        return True
    # fallback: check name/description for common hints
    name_desc = ((repo.get("name") or "") + " " + (repo.get("description") or "")).lower()
    hints = ["systemverilog", "system-verilog", "verilog", ".sv", ".v", "hdl"]
    if any(h in name_desc for h in hints):
        return True
    return False

def simplify_repo_obj(r):
    return {
        "full_name": r["full_name"],
        "html_url": r.get("html_url"),
        "clone_url": r.get("clone_url"),
        "stargazers_count": r.get("stargazers_count", 0),
        "language": r.get("language"),
        "created_at": r.get("created_at"),
        "description": r.get("description"),
    }

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--min-stars", type=int, default=50, help="minimum stars to include")
    parser.add_argument("--clone", action="store_true", help="shallow clone matching repos into ./repos/")
    parser.add_argument("--out", default="repos_openhw.json", help="output JSON path")
    parser.add_argument("--max-pages-search", type=int, default=5)
    parser.add_argument("--max-pages-org", type=int, default=10)
    args = parser.parse_args()

    # Build search query (no created filter)
    q = f"(language:SystemVerilog OR language:Verilog) stars:>={args.min_stars}"
    print("Search query:", q)
    search_results = search_repos(q, per_page=50, max_pages=args.max_pages_search)
    print("Search found:", len(search_results))

    # Collect org repos
    org_results = []
    for org in ORG_LIST:
        print("Listing repos for org:", org)
        org_repos = list_org_repos(org, per_page=100, max_pages=args.max_pages_org)
        print(f"  {org}: found {len(org_repos)} repos")
        org_results.extend(org_repos)

    # Explicit single repos
    explicit_results = []
    for full in EXPLICIT_REPOS:
        print("Fetching explicit repo:", full)
        r = get_repo(full)
        if r:
            explicit_results.append(r)
        time.sleep(0.2)

    # Combine and dedupe by full_name
    combined = {}
    for r in (search_results + org_results + explicit_results):
        if not r or "full_name" not in r:
            continue
        name = r["full_name"]
        if name in combined:
            # keep the one with higher stars (or existing)
            if r.get("stargazers_count", 0) > combined[name].get("stargazers_count", 0):
                combined[name] = r
            continue
        combined[name] = r

    # Filter combined by min-stars and language heuristic
    final = {}
    for name, r in combined.items():
        stars = r.get("stargazers_count", 0)
        if stars < args.min_stars:
            # skip repos below threshold
            continue
        if not repo_matches_language(r):
            # skip repos that don't look like Verilog/SystemVerilog
            continue
        final[name] = r

    # Prepare simplified list and optionally clone
    simplified = []
    for name, r in sorted(final.items(), key=lambda x: (-x[1].get("stargazers_count", 0), x[0])):
        info = simplify_repo_obj(r)
        simplified.append(info)
        if args.clone:
            try:
                clone_repo(r["clone_url"], "./repos")
            except Exception as e:
                print("clone failed", r["full_name"], e)
        time.sleep(0.2)

    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(simplified, f, indent=2, ensure_ascii=False)

    print("Wrote", args.out, "repos:", len(simplified))

if __name__ == "__main__":
    main()

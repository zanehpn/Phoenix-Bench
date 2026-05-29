#!/usr/bin/env python3
"""
crawl_and_filter_prs.py (extended)
- 输入 repos.json（fetch_repos.py 的输出）
- 对每个 repo 列出 closed PRs（按页），对 PR:
    - 确认 merged (merged_at != null 或 via GraphQL merged)
    - 检查是否关联 issue (GraphQL closingIssuesReferences 或 PR body 包含 fixes/closes)
    - 获取 PR 的 files (additions + deletions -> lines_changed; files_changed = len(files))
    - 保留 files_changed <= 5 and lines_changed <= 100
    - **仅当 PR 的改动文件中包含 .v 或 .sv 文件时才视为 candidate**
- 对每个 candidate:
    - 获取 PR 详细（base.sha, head.sha）
    - 下载 base commit 的 tarball (保存到 snapshots/)
    - 下载 PR 的 patch (patch_url -> patches/)
    - 对每个修改文件，尝试获取文件在 base/head 的内容（contents API），把文本放进 JSON
- 输出 candidates.json（包含 metadata + 本地路径 + patch + file contents）
"""
import os
import requests
import time
import json
import argparse
import base64
import re
from urllib.parse import quote

GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")
if not GITHUB_TOKEN:
    raise SystemExit("请先在环境变量中设置 GITHUB_TOKEN")

HEADERS = {"Authorization": f"token {GITHUB_TOKEN}", "Accept": "application/vnd.github.v3+json"}
GRAPHQL_URL = "https://api.github.com/graphql"
REST_BASE = "https://api.github.com"

# thresholds
MAX_FILES = 5
MAX_LINES = 100

# storage dirs
SNAPSHOT_DIR = "snapshots"
PATCH_DIR = "patches"
os.makedirs(SNAPSHOT_DIR, exist_ok=True)
os.makedirs(PATCH_DIR, exist_ok=True)

def graphql_query(q, variables=None):
    r = requests.post(GRAPHQL_URL, json={"query": q, "variables": variables}, headers=HEADERS)
    if r.status_code != 200:
        print("GraphQL error", r.status_code, r.text)
        return None
    return r.json()

def fetch_closed_prs(owner, repo, per_page=50, max_pages=10):
    prs = []
    for page in range(1, max_pages+1):
        url = f"{REST_BASE}/repos/{owner}/{repo}/pulls"
        params = {"state": "closed", "per_page": per_page, "page": page}
        r = requests.get(url, headers=HEADERS, params=params)
        if r.status_code == 404:
            break
        if r.status_code != 200:
            print("Error fetching pulls:", r.status_code, r.text)
            break
        data = r.json()
        if not data:
            break
        prs.extend(data)
        if "next" not in r.links:
            break
        time.sleep(0.5)
    return prs

def is_pr_merged(owner, repo, pr_number):
    url = f"{REST_BASE}/repos/{owner}/{repo}/pulls/{pr_number}"
    r = requests.get(url, headers=HEADERS)
    if r.status_code != 200:
        return False
    pr = r.json()
    return pr.get("merged", False) or (pr.get("merged_at") is not None)

def pr_closing_issues_via_graphql(owner, repo, pr_number):
    # Use GitHub GraphQL to query closingIssuesReferences
    q = """
    query($owner: String!, $name: String!, $number: Int!) {
      repository(owner: $owner, name: $name) {
        pullRequest(number: $number) {
          number
          closingIssuesReferences(first: 10) {
            totalCount
            nodes {
              number
              title
              url
            }
          }
        }
      }
    }
    """
    variables = {"owner": owner, "name": repo, "number": pr_number}
    res = graphql_query(q, variables)
    try:
        crefs = res["data"]["repository"]["pullRequest"]["closingIssuesReferences"]
        return crefs.get("totalCount", 0) > 0, crefs.get("nodes", [])
    except Exception:
        return False, []

def pr_files_and_stats(owner, repo, pr_number):
    files = []
    page = 1
    per_page = 100
    total_add = total_del = 0
    while True:
        url = f"{REST_BASE}/repos/{owner}/{repo}/pulls/{pr_number}/files"
        params = {"per_page": per_page, "page": page}
        r = requests.get(url, headers=HEADERS, params=params)
        if r.status_code != 200:
            print("files api err", r.status_code, r.text)
            break
        data = r.json()
        if not data:
            break
        for f in data:
            files.append({"filename": f["filename"], "additions": f["additions"], "deletions": f["deletions"], "changes": f["changes"], "status": f.get("status")})
            total_add += f["additions"] or 0
            total_del += f["deletions"] or 0
        if "next" not in r.links:
            break
        page += 1
        time.sleep(0.2)
    return files, total_add + total_del

def simple_body_linked_issue(pr_body):
    if not pr_body:
        return False
    lower = pr_body.lower()
    keys = ["fixes #", "closes #", "resolves #", "fixes https://github.com", "closes https://github.com"]
    return any(k in lower for k in keys)

def sanitize_fname(s: str):
    # simple sanitize for filenames
    return re.sub(r"[^0-9A-Za-z._-]", "_", s)

def get_pr_details(owner, repo, pr_number):
    url = f"{REST_BASE}/repos/{owner}/{repo}/pulls/{pr_number}"
    r = requests.get(url, headers=HEADERS)
    if r.status_code != 200:
        print("Error getting PR details", r.status_code, r.text)
        return None
    return r.json()

def download_repo_tarball(owner, repo, sha, out_dir=SNAPSHOT_DIR):
    """
    下载指定 commit/sha 的 tarball，保存为 snapshots/{owner_repo}_sha.tar.gz
    """
    fname = f"{sanitize_fname(owner+'_'+repo+'_'+sha)}.tar.gz"
    path = os.path.join(out_dir, fname)
    if os.path.exists(path):
        return path
    url = f"{REST_BASE}/repos/{owner}/{repo}/tarball/{sha}"
    with requests.get(url, headers=HEADERS, stream=True) as r:
        if r.status_code != 200:
            print("tarball download failed", owner, repo, sha, r.status_code)
            return None
        with open(path, "wb") as f:
            for chunk in r.iter_content(chunk_size=8192):
                if chunk:
                    f.write(chunk)
    return path

def download_pr_patch(pr_json, out_dir=PATCH_DIR):
    """
    pr_json 是 PR 对象（REST），使用 patch_url/ diff_url 字段下载 patch 文本
    """
    patch_url = pr_json.get("patch_url")
    if not patch_url:
        return None
    # filename
    owner_repo = pr_json.get("base", {}).get("repo", {}).get("full_name", "unknown_repo")
    prnum = pr_json.get("number")
    fname = f"{sanitize_fname(owner_repo)}_pr{prnum}.patch"
    path = os.path.join(out_dir, fname)
    if os.path.exists(path):
        return path
    r = requests.get(patch_url, headers=HEADERS)
    if r.status_code == 200:
        with open(path, "w", encoding="utf-8") as f:
            f.write(r.text)
        return path
    else:
        print("patch download failed", patch_url, r.status_code)
        return None

def get_file_content_at_ref(owner, repo, path, ref_sha):
    """
    使用 contents API 获取指定 ref (sha) 下的文件内容（base64），返回解码后的文本或 None
    """
    # contents API: /repos/{owner}/{repo}/contents/{path}?ref={ref}
    # path 可能包含特殊字符，requests 会处理 params
    url = f"{REST_BASE}/repos/{owner}/{repo}/contents/{quote(path, safe='')}"
    params = {"ref": ref_sha}
    r = requests.get(url, headers=HEADERS, params=params)
    if r.status_code == 200:
        try:
            j = r.json()
            if isinstance(j, list):
                # directory listing: not expected for file; return None
                return None
            content = j.get("content")
            encoding = j.get("encoding")
            if content and encoding == "base64":
                text = base64.b64decode(content).decode("utf-8", errors="replace")
                return text
            else:
                return None
        except Exception as e:
            print("decode contents json err", e)
            return None
    elif r.status_code == 404:
        # file might be deleted/renamed in that ref
        return None
    else:
        print("contents API error", r.status_code, r.text)
        return None

def pr_contains_hdl_files(files):
    """
    检查 PR 的变更文件列表中是否包含 .v 或 .sv 文件（大小写不敏感）。
    返回 True/False。
    """
    for f in files:
        fn = f.get("filename", "")
        if not fn:
            continue
        low = fn.lower()
        if low.endswith(".v") or low.endswith(".sv"):
            return True
    return False

def process_repo(repo_item, out_list, rate_sleep=0.5, max_prs_per_repo=None):
    full = repo_item["full_name"]
    owner, name = full.split("/")
    print("Processing repo:", full)
    prs = fetch_closed_prs(owner, name, per_page=50, max_pages=5)
    print("  closed PRs fetched:", len(prs))
    count = 0
    for pr in prs:
        if max_prs_per_repo and count>=max_prs_per_repo:
            break
        pr_number = pr["number"]
        merged = pr.get("merged", None)
        # sometimes REST pull contains merged flag; if missing, perform explicit check
        if merged is False:
            continue
        if merged is None:
            merged = is_pr_merged(owner, name, pr_number)
        if not merged:
            continue
        # check linked issue: prefer GraphQL closingIssuesReferences, fallback to look for keywords in body
        linked, nodes = pr_closing_issues_via_graphql(owner, name, pr_number)
        if not linked:
            if simple_body_linked_issue(pr.get("body", "")):
                linked = True
        if not linked:
            continue
        # fetch files and stats
        files, lines_changed = pr_files_and_stats(owner, name, pr_number)
        files_changed = len(files)

        # NEW: only accept PRs that modify at least one .v or .sv file
        if not pr_contains_hdl_files(files):
            # skip this PR - no HDL (.v/.sv) changes
            # print a short message for debugging / monitoring
            print(f"   - skip PR {owner}/{name}#{pr_number}: no .v/.sv files changed")
            count += 1
            time.sleep(rate_sleep)
            continue

        # apply thresholds
        if files_changed <= MAX_FILES and lines_changed <= MAX_LINES:
            # -> candidate: gather more artifacts
            pr_detail = get_pr_details(owner, name, pr_number)
            base_sha = None
            head_sha = None
            if pr_detail:
                base_sha = pr_detail.get("base", {}).get("sha")
                head_sha = pr_detail.get("head", {}).get("sha")
            # download base tarball snapshot
            snapshot_path = None
            if base_sha:
                snapshot_path = download_repo_tarball(owner, name, base_sha)
            # download patch
            patch_path = None
            if pr_detail:
                patch_path = download_pr_patch(pr_detail)
            # for each file, try fetch content at base and head
            file_entries = []
            for f in files:
                fname = f["filename"]
                content_base = None
                content_head = None
                try:
                    if base_sha:
                        content_base = get_file_content_at_ref(owner, name, fname, base_sha)
                        # be polite
                        time.sleep(0.1)
                    if head_sha:
                        content_head = get_file_content_at_ref(owner, name, fname, head_sha)
                        time.sleep(0.1)
                except Exception as e:
                    print("file content fetch err", fname, e)
                file_entry = dict(f)  # copy basic metadata
                file_entry.update({
                    "content_base": content_base,
                    "content_head": content_head
                })
                file_entries.append(file_entry)
            candidate = {
                "repo": full,
                "pr_number": pr_number,
                "pr_title": pr.get("title"),
                "pr_url": pr.get("html_url"),
                "merged_at": pr.get("merged_at"),
                "author": pr.get("user", {}).get("login"),
                "files_changed": files_changed,
                "lines_changed": lines_changed,
                "files": file_entries,
                "closing_issues": nodes,
                "base_sha": base_sha,
                "head_sha": head_sha,
                "snapshot_tarball": snapshot_path,
                "patch_path": patch_path
            }
            out_list.append(candidate)
            print("   + candidate:", full, pr_number, "files:", files_changed, "lines:", lines_changed, "snapshot:", snapshot_path, "patch:", patch_path)
        count += 1
        time.sleep(rate_sleep)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--repos", default="repos.json", help="input repos file from fetch_repos.py")
    parser.add_argument("--out", default="candidates.json")
    parser.add_argument("--max-repos", type=int, default=200)
    parser.add_argument("--max-prs-per-repo", type=int, default=50)
    args = parser.parse_args()

    with open(args.repos, "r", encoding="utf-8") as f:
        repos = json.load(f)
    candidates = []
    for i, r in enumerate(repos):
        if i>=args.max_repos:
            break
        try:
            process_repo(r, candidates, max_prs_per_repo=args.max_prs_per_repo)
        except Exception as e:
            print("repo proc err", r.get("full_name"), e)
        time.sleep(0.5)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(candidates, f, indent=2, ensure_ascii=False)
    print("Wrote", args.out, "candidates:", len(candidates))

if __name__ == "__main__":
    main()

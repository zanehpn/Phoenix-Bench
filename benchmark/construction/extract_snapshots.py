#!/usr/bin/env python3
"""
extract_snapshots.py

用法示例：
    python3 extract_snapshots.py /workspace/phoenix-bench/openhw2/openhw_candidates2.json

脚本行为：
- 读取 JSON 列表（每个元素为一个 candidate dict）
- 对每个元素，获取 snapshot_tarball 字段（相对或绝对路径）
- 如果文件存在，解压到 <json_parent_dir>/snapshot/<owner_repo>_pr<pr_number>/
- 如果找不到，会尝试把路径中的 "snapshots/" <-> "snapshot/" 互换一次再查找
- 已解压（目标目录存在且非空）则跳过
"""
import os
import sys
import json
import tarfile
import argparse

def sanitize(s: str) -> str:
    # 用于生成目录名：把 '/' 替换为 '_' 并去掉不安全字符
    import re
    return re.sub(r"[^0-9A-Za-z._-]", "_", s.replace("/", "_"))

def safe_extract(tar: tarfile.TarFile, path: str) -> None:
    """
    安全地解压 tar 到 path（防止路径穿越）
    """
    for member in tar.getmembers():
        member_name = member.name
        # 安全检查：构造目标路径，然后确保它仍在 path 子树内
        dest = os.path.join(path, member_name)
        dest_norm = os.path.normpath(os.path.abspath(dest))
        path_norm = os.path.normpath(os.path.abspath(path))
        if not dest_norm.startswith(path_norm + os.sep) and dest_norm != path_norm:
            raise Exception(f"Unsafe tar member path detected: {member_name}")
    tar.extractall(path=path)

def find_tarball(base_dir: str, indicated_path: str) -> str:
    """
    尝试定位 tarball。先按 indicated_path（可能是相对或绝对）查找，
    若不存在，尝试把 snapshots/ <-> snapshot/ 替换一次再查找。
    返回找到的绝对路径，找不到返回空字符串。
    """
    # 如果是绝对路径，先试绝对
    if os.path.isabs(indicated_path):
        if os.path.isfile(indicated_path):
            return indicated_path
    # 以 base_dir 为根解析相对路径
    candidate = os.path.join(base_dir, indicated_path)
    if os.path.isfile(candidate):
        return os.path.abspath(candidate)
    # 尝试替换 snapshots/ <-> snapshot/
    swapped = None
    if "snapshots/" in indicated_path:
        swapped = indicated_path.replace("snapshots/", "snapshot/", 1)
    elif "snapshot/" in indicated_path:
        swapped = indicated_path.replace("snapshot/", "snapshots/", 1)

    if swapped:
        candidate2 = os.path.join(base_dir, swapped)
        if os.path.isfile(candidate2):
            return os.path.abspath(candidate2)
        # 也试绝对 swapped（以防用户给绝对但写错）
        if os.path.isabs(swapped) and os.path.isfile(swapped):
            return os.path.abspath(swapped)
    # 还没找到：尝试 base_dir/<indicated_basename>
    basename = os.path.basename(indicated_path)
    candidate3 = os.path.join(base_dir, basename)
    if os.path.isfile(candidate3):
        return os.path.abspath(candidate3)
    return ""

def main():
    p = argparse.ArgumentParser(description="Extract snapshot tarballs listed in a candidates JSON.")
    p.add_argument("json_path", help="Path to the candidates JSON (list of items).")
    p.add_argument("--out-root", default=None, help="Root folder to create per-item snapshot dirs (default: <json_parent>/snapshot)")
    args = p.parse_args()

    json_path = args.json_path
    if not os.path.isfile(json_path):
        print("JSON file not found:", json_path)
        sys.exit(2)

    json_parent = os.path.dirname(os.path.abspath(json_path))
    if args.out_root:
        out_root = os.path.abspath(args.out_root)
    else:
        out_root = os.path.join(json_parent, "snapshot_expand")   # 注意：使用 singular 'snapshot'，与你盘点的目录一致
    os.makedirs(out_root, exist_ok=True)

    with open(json_path, "r", encoding="utf-8") as f:
        try:
            items = json.load(f)
        except Exception as e:
            print("Failed to parse JSON:", e)
            sys.exit(3)

    if not isinstance(items, list):
        print("Expected top-level JSON array (list).")
        sys.exit(4)

    print(f"Found {len(items)} items in {json_path}.")
    for idx, item in enumerate(items, start=1):
        try:
            repo = item.get("repo") or item.get("repository") or ""
            pr_number = item.get("pr_number") or item.get("number") or "unknown"
            snapshot_field = item.get("snapshot_tarball") or item.get("snapshot") or ""
            if not snapshot_field:
                print(f"[{idx}] {repo}#{pr_number}: no snapshot_tarball field, skip.")
                continue

            # 构造目标解压目录名，使用 repo -> owner_repo（'pulp-platform/axi' -> 'pulp-platform_axi'）
            owner_repo = repo.replace("/", "_")
            sanitized = sanitize(owner_repo)
            out_dir_name = f"{sanitized}_pr{pr_number}"
            target_dir = os.path.join(out_root, out_dir_name)

            if os.path.isdir(target_dir) and os.listdir(target_dir):
                print(f"[{idx}] {repo}#{pr_number}: target {target_dir} already exists and not empty — skip.")
                continue

            # 尝试定位 tarball（以 JSON 文件所在目录为基准）
            tarball_path = find_tarball(json_parent, snapshot_field)
            if not tarball_path:
                print(f"[{idx}] {repo}#{pr_number}: tarball not found for '{snapshot_field}' (tried relative to {json_parent}). Skipping.")
                continue

            print(f"[{idx}] {repo}#{pr_number}: found tarball: {tarball_path}")
            os.makedirs(target_dir, exist_ok=True)

            # 解压
            try:
                with tarfile.open(tarball_path, "r:gz") as tar:
                    safe_extract(tar, target_dir)
                print(f"    -> extracted to {target_dir}")
            except Exception as e:
                print(f"    Extraction failed for {tarball_path}: {e}")
                # 如果解压失败，尝试清理目标目录（谨慎），以便重试
                # 仅在目录为空或包含部分内容时不删除。这里只报告错误并继续。
        except Exception as e:
            print(f"[{idx}] Unexpected error processing item: {e}")

    print("Done.")

if __name__ == "__main__":
    main()

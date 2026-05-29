from pathlib import Path

snapshots_DIR = Path("/workspace/phoenix-bench/data/snapshots")
PATCH_DIR     = Path("/workspace/phoenix-bench/data/patches")
ISSUE_DIR     = Path("/workspace/phoenix-bench/data/issues")

def must_dir(p: Path) -> None:
    if not p.is_dir():
        raise FileNotFoundError(f"Not a directory: {p}")

def stem(name: str) -> str:
    """Remove extension once (xxx.patch -> xxx)."""
    return Path(name).stem

def list_snapshots_names(tb_dir: Path) -> set[str]:
    # only folders under snapshots
    return {p.name for p in tb_dir.iterdir() if p.is_dir()}

def list_patch_names(patch_dir: Path) -> set[str]:
    # only *.patch under patches, use stem
    return {stem(p.name) for p in patch_dir.glob("*.patch") if p.is_file()}

def list_issue_names(issue_dir: Path) -> set[str]:
    # files + folders under issues, keep full name (no stem by default)
    return {p.name for p in issue_dir.iterdir() if p.is_dir() or p.is_file()}

def print_list(title: str, items: list[str]) -> None:
    print(f"{title}: {len(items)}")
    for x in items:
        print(f"  - {x}")
    print()

def main():
    must_dir(snapshots_DIR)
    must_dir(PATCH_DIR)
    must_dir(ISSUE_DIR)

    tb_names     = list_snapshots_names(snapshots_DIR)
    patch_names  = list_patch_names(PATCH_DIR)
    issue_names  = list_issue_names(ISSUE_DIR)

    expected = patch_names | issue_names  # names that "should exist" in tb (by your ask)

    # snapshots vs expected(patches+issues)
    tb_missing = sorted(expected - tb_names)   # patches/issues have, tb doesn't
    tb_extra   = sorted(tb_names - expected)   # tb has, but no patch/issue

    # optional: patch vs issue mismatch (helps find naming inconsistency)
    patch_only = sorted(patch_names - issue_names)
    issue_only = sorted(issue_names - patch_names)

    print("====== Counts ======")
    print(f"snapshots dirs : {len(tb_names)}")
    print(f"patches (*.patch stems): {len(patch_names)}")
    print(f"issues entries : {len(issue_names)}")
    print()

    print_list("❌ snapshots 缺少 (patches/issues 有，但 snapshots 没有)", tb_missing)
    print_list("⚠️ snapshots 多出 (snapshots 有，但 patches/issues 都没有)", tb_extra)

    # extra helpful comparisons
    print_list("ℹ️ patches 有但 issues 没有 (可能 issues 命名/缺失)", patch_only)
    print_list("ℹ️ issues 有但 patches 没有 (可能 patch 命名/缺失)", issue_only)

if __name__ == "__main__":
    main()

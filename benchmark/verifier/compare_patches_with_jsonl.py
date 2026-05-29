import json
from pathlib import Path

JSONL_PATH = Path("/workspace/phoenix-bench/data/candidates_test.jsonl")
PATCH_DIR  = Path("/workspace/phoenix-bench/data/patches")

def norm_patch_path(p: str) -> str:
    """
    Normalize patch_path from jsonl.
    Examples:
      "patches/lowRISC_opentitan_pr28698.patch" -> "lowRISC_opentitan_pr28698.patch"
      "lowRISC_opentitan_pr28698.patch"         -> "lowRISC_opentitan_pr28698.patch"
      "/abs/path/.../patches/xxx.patch"         -> "xxx.patch"
    """
    if not p:
        return ""
    p = p.strip()
    # Take only the filename part
    return Path(p).name

def read_patch_names_from_jsonl(jsonl_path: Path) -> set[str]:
    patch_names = set()
    bad_lines = 0

    with jsonl_path.open("r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                bad_lines += 1
                continue

            patch_path = obj.get("patch_path", "")
            name = norm_patch_path(patch_path)
            if name:
                patch_names.add(name)

    if bad_lines:
        print(f"[WARN] Skipped {bad_lines} non-JSON lines in {jsonl_path}")
    return patch_names

def list_patch_files_in_dir(patch_dir: Path) -> set[str]:
    if not patch_dir.is_dir():
        raise FileNotFoundError(f"Patch dir not found: {patch_dir}")
    return {p.name for p in patch_dir.glob("*.patch")}

def main():
    jsonl_patches = read_patch_names_from_jsonl(JSONL_PATH)
    dir_patches   = list_patch_files_in_dir(PATCH_DIR)

    missing_in_dir = sorted(jsonl_patches - dir_patches)
    extra_in_dir   = sorted(dir_patches - jsonl_patches)

    print(f"JSONL patch_path count: {len(jsonl_patches)}")
    print(f"Dir *.patch count:      {len(dir_patches)}")
    print()

    print(f"Missing in {PATCH_DIR} (mentioned in JSONL but file not present): {len(missing_in_dir)}")
    for x in missing_in_dir:
        print(f"  - {x}")
    print()

    print(f"Extra in {PATCH_DIR} (present in dir but not mentioned in JSONL): {len(extra_in_dir)}")
    for x in extra_in_dir:
        print(f"  - {x}")

if __name__ == "__main__":
    main()

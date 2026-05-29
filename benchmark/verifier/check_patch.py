import json
from pathlib import Path
from collections import defaultdict

JSONL_IN  = Path("/workspace/phoenix-bench/data/candidates_test.jsonl")
JSONL_OUT = Path("/workspace/phoenix-bench/data/candidates_test_dedup_by_patch.jsonl")

def norm_patch_path(p: str) -> str:
    if not p:
        return ""
    return Path(str(p).strip()).name  # only filename

def short_id(obj: dict) -> str:
    repo = obj.get("repo", "?")
    pr   = obj.get("pr_number", "?")
    return f"{repo}#${pr}".replace("#$", "#")  # just formatting

def main():
    total_lines = 0
    bad_json_lines = 0
    empty_patch_lines = []  # store (line_no, id, raw_patch_path)

    # patch_name -> list of (line_no, obj)
    by_patch = defaultdict(list)

    with JSONL_IN.open("r", encoding="utf-8") as f:
        for line_no, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            total_lines += 1
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                bad_json_lines += 1
                continue

            patch_raw = obj.get("patch_path", "")
            patch_name = norm_patch_path(patch_raw)

            if not patch_name:
                empty_patch_lines.append((line_no, short_id(obj), patch_raw))
                continue

            by_patch[patch_name].append((line_no, obj))

    # Summary counts
    unique_patches = len(by_patch)
    dup_patches = {k: v for k, v in by_patch.items() if len(v) > 1}

    print("=== SUMMARY ===")
    print(f"Input file: {JSONL_IN}")
    print(f"Total non-empty lines read: {total_lines}")
    print(f"Bad JSON lines skipped:     {bad_json_lines}")
    print(f"Items with empty patch_path:{len(empty_patch_lines)}")
    print(f"Unique patch filenames:     {unique_patches}")
    print(f"Patches with duplicates:    {len(dup_patches)}")
    print()

    # Print empty patch_path items
    if empty_patch_lines:
        print("=== EMPTY / MISSING patch_path ITEMS ===")
        for (ln, sid, raw) in empty_patch_lines:
            print(f"  line {ln}: {sid}  patch_path={raw!r}")
        print()

    # Print duplicates (this is your “73 but 70” root cause)
    if dup_patches:
        print("=== DUPLICATE patch_path (same patch appears in multiple items) ===")
        # sort by multiplicity desc
        for patch_name, entries in sorted(dup_patches.items(), key=lambda kv: len(kv[1]), reverse=True):
            ids = [f"line {ln} {short_id(obj)}" for (ln, obj) in entries]
            print(f"- {patch_name}: {len(entries)} occurrences")
            for s in ids:
                print(f"    {s}")
        print()

    # Dedup: keep first occurrence per patch
    kept = []
    dropped = []
    for patch_name, entries in by_patch.items():
        # keep smallest line_no (first appearance)
        entries_sorted = sorted(entries, key=lambda x: x[0])
        keep_ln, keep_obj = entries_sorted[0]
        kept.append((keep_ln, keep_obj))
        for ln, obj in entries_sorted[1:]:
            dropped.append((ln, patch_name, short_id(obj)))

    kept.sort(key=lambda x: x[0])  # preserve original order as much as possible

    # Write output jsonl
    with JSONL_OUT.open("w", encoding="utf-8") as out:
        for _, obj in kept:
            out.write(json.dumps(obj, ensure_ascii=False) + "\n")

    print("=== DEDUP OUTPUT ===")
    print(f"Output file: {JSONL_OUT}")
    print(f"Kept items (one per patch): {len(kept)}")
    print(f"Dropped duplicate items:    {len(dropped)}")
    if dropped:
        print("Examples of dropped:")
        for ln, patch_name, sid in dropped[:20]:
            print(f"  dropped line {ln}: {sid} (patch {patch_name})")

if __name__ == "__main__":
    main()

import json
import re
import sys
from pathlib import Path

BASE_DIR = Path(__file__).resolve().parent
JSONL_IN = BASE_DIR / "candidates_test.jsonl"
ISSUES_DIR = BASE_DIR / "issues"
OUTPUT_FILE = BASE_DIR / "swe_instances.jsonl"
TAG_PREFIX = "hwebench"


def sanitize_repo_name(name: str) -> str:
    sanitized = re.sub(r"[^a-z0-9._-]+", "-", name.lower())
    sanitized = re.sub(r"[._-]{2,}", lambda match: match.group(0)[0], sanitized)
    sanitized = sanitized.strip("._-")
    return sanitized

def build_instance_id(repo, pr_number):
    if not repo or pr_number is None:
        return None
    if "/" not in repo:
        return None
    owner, name = repo.split("/", 1)
    if not owner or not name:
        return None
    return f"{owner}_{name}_pr{pr_number}"


def build_image_name(repo, pr_number, tag_prefix=TAG_PREFIX):
    if not repo or pr_number is None:
        return None
    if "/" in repo:
        owner, repo_name = repo.split("/", 1)
        raw_repo_name = f"{owner}_{repo_name}"
    else:
        raw_repo_name = repo
    repo_name = sanitize_repo_name(raw_repo_name)
    if not repo_name:
        return None
    return f"{tag_prefix}/{repo_name}:pr{pr_number}"


def find_issue_text(instance_id):
    if not instance_id:
        return None
    for suffix in ("", ".md", ".txt"):
        path = ISSUES_DIR / f"{instance_id}{suffix}"
        if path.is_file():
            return path.read_text(encoding="utf-8")
    return None


def read_patch_text(patch_path):
    if not patch_path:
        return None
    path = Path(str(patch_path))
    if not path.is_absolute():
        path = BASE_DIR / path
    if not path.is_file():
        return None
    return path.read_text(encoding="utf-8")


def report_missing(identifier, missing_fields):
    fields = ", ".join(missing_fields)
    print(f"Missing fields for {identifier}: {fields}", file=sys.stderr)


def main():
    if not JSONL_IN.is_file():
        print(f"Input file not found: {JSONL_IN}", file=sys.stderr)
        return 1
    if not ISSUES_DIR.is_dir():
        print(f"Issues directory not found: {ISSUES_DIR}", file=sys.stderr)
        return 1

    total_lines = 0
    bad_json_lines = 0
    written = 0
    skipped = 0

    with JSONL_IN.open("r", encoding="utf-8") as f_in, OUTPUT_FILE.open(
        "w", encoding="utf-8"
    ) as f_out:
        for line_no, line in enumerate(f_in, 1):
            line = line.strip()
            if not line:
                continue
            total_lines += 1
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                bad_json_lines += 1
                print(f"Line {line_no}: invalid JSON", file=sys.stderr)
                continue

            repo = obj.get("repo")
            pr_number = obj.get("pr_number")
            base_sha = obj.get("base_sha")
            patch_path = obj.get("patch_path")

            missing = []

            if not repo:
                missing.append("repo")
            if pr_number is None:
                missing.append("pr_number")

            instance_id = build_instance_id(repo, pr_number)
            if not instance_id:
                missing.append("instance_id")

            image_name = build_image_name(repo, pr_number)
            if not image_name:
                missing.append("image_name")

            issue_text = find_issue_text(instance_id)
            if issue_text is None:
                missing.append("problem_statement")

            if not base_sha:
                missing.append("base_commit")

            patch_text = read_patch_text(patch_path)
            if patch_text is None:
                missing.append("patch")

            if missing:
                skipped += 1
                identifier = instance_id or f"line {line_no}"
                report_missing(identifier, missing)
                continue

            instance = {
                "instance_id": instance_id,
                "repo": repo,
                "pr_number": pr_number,
                "base_commit": base_sha,
                "image_name": image_name,
                "repo_name": "testbed",
                "problem_statement": issue_text,
                #"patch": patch_text,
            }
            f_out.write(json.dumps(instance, ensure_ascii=False) + "\n")
            written += 1

    print(f"Input lines processed: {total_lines}")
    print(f"Invalid JSON lines: {bad_json_lines}")
    print(f"Instances written: {written}")
    print(f"Instances skipped (missing fields): {skipped}")
    print(f"Output file: {OUTPUT_FILE}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

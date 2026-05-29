#!/usr/bin/env python3
import argparse
import json
from pathlib import Path


def _safe_name(name: str) -> str:
    return name.replace("/", "__")


def _resolve_input_path(results_root: Path, model_name: str) -> Path:
    candidates = []
    for candidate_dir in [model_name, _safe_name(model_name), ""]:
        if candidate_dir:
            candidate = (
                results_root / candidate_dir / "output_0_processed.jsonl"
            ).resolve()
        else:
            candidate = (results_root / "output_0_processed.jsonl").resolve()
        candidates.append(candidate)
        if candidate.exists():
            return candidate

    joined = "\n".join(str(p) for p in candidates)
    raise FileNotFoundError(
        "Could not find output_0_processed.jsonl for model. Checked:\n" + joined
    )


def _load_jsonl(path: Path) -> list[dict]:
    rows = []
    with path.open("r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rows.append(json.loads(line))
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Build OpenHands-style solutions jsonl from Agentless repair outputs."
        )
    )
    parser.add_argument("--model_name", required=True, help="Model name to collect.")
    parser.add_argument(
        "--results_root",
        default="/workspace/phoenix-bench/Agentless/results/hwe-bench-lite/repair_sample_verilog",
        help="Root folder containing <model_name>/output_0_processed.jsonl.",
    )
    parser.add_argument(
        "--dataset_path",
        default="/workspace/phoenix-bench/Agentless/agentless_dataset.json",
        help="Agentless dataset json used for repo_name mapping.",
    )
    parser.add_argument(
        "--output_path",
        default="",
        help=(
            "Output jsonl path. Defaults to "
            "agentless_solutions_<model_name>_<dataset_size>.jsonl in Agentless root."
        ),
    )
    args = parser.parse_args()

    script_dir = Path(__file__).resolve().parent
    results_root = Path(args.results_root).resolve()
    dataset_path = Path(args.dataset_path).resolve()

    input_path = _resolve_input_path(results_root, args.model_name)

    with dataset_path.open("r", encoding="utf-8") as f:
        dataset = json.load(f)

    patches = _load_jsonl(input_path)
    patch_by_instance = {}
    for row in patches:
        instance_id = row.get("instance_id")
        if not instance_id:
            continue
        patch_by_instance[instance_id] = row.get("model_patch", "")

    output_path = (
        Path(args.output_path).resolve()
        if args.output_path
        else (
            script_dir
            / f"agentless_solutions_{_safe_name(args.model_name)}_{len(dataset)}.jsonl"
        ).resolve()
    )
    output_path.parent.mkdir(parents=True, exist_ok=True)

    missing = 0
    with output_path.open("w", encoding="utf-8") as f:
        for item in dataset:
            instance_id = item["instance_id"]
            solution = patch_by_instance.get(instance_id, "")
            if instance_id not in patch_by_instance:
                missing += 1
            out = {
                "repo_name": item["repo"],
                "solution": solution,
            }
            f.write(json.dumps(out, ensure_ascii=False) + "\n")

    print(f"Input:  {input_path}")
    print(f"Output: {output_path}")
    print(f"Rows:   {len(dataset)}")
    print(f"Missing patches filled with empty solution: {missing}")


if __name__ == "__main__":
    main()

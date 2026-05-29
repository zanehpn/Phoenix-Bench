#!/usr/bin/env python3

from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable


DEFAULT_BASE_DIR = Path(__file__).resolve().parent / "results"


@dataclass
class TokenUsage:
    records: int = 0
    usage_objects: int = 0
    prompt_tokens: int = 0
    completion_tokens: int = 0
    embedding_tokens: int = 0
    cache_creation_tokens: int = 0
    cache_read_tokens: int = 0

    @property
    def total_text_tokens(self) -> int:
        return self.prompt_tokens + self.completion_tokens

    @property
    def total_tokens(self) -> int:
        return (
            self.prompt_tokens
            + self.completion_tokens
            + self.embedding_tokens
            + self.cache_creation_tokens
            + self.cache_read_tokens
        )

    def add_usage(self, usage: dict[str, Any]) -> None:
        self.usage_objects += 1
        self.prompt_tokens += first_int(
            usage, "prompt_tokens", "input_tokens"
        )
        self.completion_tokens += first_int(
            usage, "completion_tokens", "output_tokens"
        )
        self.embedding_tokens += first_int(usage, "embedding_tokens")
        self.cache_creation_tokens += first_int(
            usage, "cache_creation_token", "cache_creation_input_tokens"
        )
        self.cache_read_tokens += first_int(
            usage, "cache_read_input_tokens", "cache_read_tokens"
        )

    def add_row(self, row: "TokenUsage") -> None:
        self.records += row.records
        self.usage_objects += row.usage_objects
        self.prompt_tokens += row.prompt_tokens
        self.completion_tokens += row.completion_tokens
        self.embedding_tokens += row.embedding_tokens
        self.cache_creation_tokens += row.cache_creation_tokens
        self.cache_read_tokens += row.cache_read_tokens


@dataclass
class ModelSummary:
    runs: int = 0
    tokens_sent: int = 0
    tokens_received: int = 0
    total_tokens: int = 0
    api_calls: int = 0

    def add_usage(self, usage: TokenUsage) -> None:
        self.runs += usage.records
        self.tokens_sent += usage.prompt_tokens
        self.tokens_received += usage.completion_tokens
        self.total_tokens += usage.total_text_tokens
        self.api_calls += usage.usage_objects


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Summarize token usage per model in Agentless JSONL outputs. By "
            "default this scans args.json files under the repo's results/ "
            "directory and tallies their declared output JSONL files."
        )
    )
    parser.add_argument(
        "--base-dir",
        type=Path,
        default=DEFAULT_BASE_DIR,
        help="A JSONL file or directory containing Agentless result JSONL files.",
    )
    parser.add_argument(
        "--format",
        choices=("table", "json"),
        default="table",
        help="Output format.",
    )
    parser.add_argument(
        "--include-zero-usage",
        action="store_true",
        help="Include models whose declared output files do not contain usage objects.",
    )
    return parser.parse_args()


def first_int(mapping: dict[str, Any], *keys: str) -> int:
    for key in keys:
        value = mapping.get(key)
        if value is None:
            continue
        try:
            return int(value)
        except (TypeError, ValueError):
            continue
    return 0


def iter_usage_objects(value: Any) -> Iterable[dict[str, Any]]:
    if isinstance(value, dict):
        usage = value.get("usage")
        if isinstance(usage, dict):
            yield usage
        for child in value.values():
            yield from iter_usage_objects(child)
    elif isinstance(value, list):
        for child in value:
            yield from iter_usage_objects(child)


def iter_jsonl_files(path: Path) -> list[Path]:
    if path.is_file():
        if path.suffix != ".jsonl":
            raise ValueError(f"{path} is not a .jsonl file")
        return [path]
    if not path.is_dir():
        raise ValueError(f"{path} is not a file or directory")
    return sorted(path.glob("**/*.jsonl"))


def load_json(path: Path) -> Any:
    with path.open(encoding="utf-8") as fh:
        return json.load(fh)


def format_model_name(args_data: dict[str, Any], fallback: str) -> str:
    model = args_data.get("model")
    backend = args_data.get("backend")
    if isinstance(model, str) and model:
        if isinstance(backend, str) and backend and "/" not in model:
            return f"{backend}/{model}"
        return model
    return fallback


def resolve_declared_output(args_path: Path, args_data: dict[str, Any]) -> Path | None:
    raw_output_file = args_data.get("output_file")
    if not isinstance(raw_output_file, str) or not raw_output_file:
        return None

    output_name = Path(raw_output_file).name
    local_output = args_path.parent / output_name
    if local_output.exists():
        return local_output

    raw_path = Path(raw_output_file)
    if raw_path.is_absolute() and raw_path.exists():
        return raw_path

    repo_relative = Path(__file__).resolve().parent / raw_path
    if repo_relative.exists():
        return repo_relative

    return None


def infer_args_for_jsonl(path: Path) -> tuple[str, list[str]]:
    warnings: list[str] = []
    for parent in [path.parent, *path.parents]:
        args_path = parent / "args.json"
        if not args_path.exists():
            continue
        try:
            args_data = load_json(args_path)
        except (OSError, json.JSONDecodeError) as exc:
            warnings.append(f"Ignoring unreadable args file {args_path}: {exc}")
            continue
        if isinstance(args_data, dict):
            return format_model_name(args_data, path.parent.name), warnings
    return path.parent.name, warnings


def collect_file_usage(path: Path) -> tuple[TokenUsage, list[str]]:
    usage = TokenUsage()
    warnings: list[str] = []

    try:
        with path.open(encoding="utf-8") as fh:
            for line_number, line in enumerate(fh, start=1):
                line = line.strip()
                if not line:
                    continue
                usage.records += 1
                try:
                    row = json.loads(line)
                except json.JSONDecodeError as exc:
                    warnings.append(f"Skipping malformed JSONL row {path}:{line_number}: {exc}")
                    continue

                for usage_object in iter_usage_objects(row):
                    usage.add_usage(usage_object)
    except OSError as exc:
        warnings.append(f"Skipping unreadable output file {path}: {exc}")

    return usage, warnings


def collect_summary(
    base_dir: Path, include_zero_usage: bool
) -> tuple[dict[str, ModelSummary], list[str]]:
    summary: dict[str, ModelSummary] = defaultdict(ModelSummary)
    warnings: list[str] = []
    seen_outputs: set[Path] = set()

    if base_dir.is_file():
        for path in iter_jsonl_files(base_dir):
            model_name, model_warnings = infer_args_for_jsonl(path)
            warnings.extend(model_warnings)
            file_usage, file_warnings = collect_file_usage(path)
            warnings.extend(file_warnings)
            if file_usage.total_text_tokens or include_zero_usage:
                summary[model_name].add_usage(file_usage)
        return dict(summary), warnings

    if not base_dir.is_dir():
        raise ValueError(f"{base_dir} is not a file or directory")

    for args_path in sorted(base_dir.glob("**/args.json")):
        try:
            args_data = load_json(args_path)
        except (OSError, json.JSONDecodeError) as exc:
            warnings.append(f"Ignoring unreadable args file {args_path}: {exc}")
            continue
        if not isinstance(args_data, dict):
            warnings.append(f"Ignoring malformed args file {args_path}: top-level JSON is not an object")
            continue

        path = resolve_declared_output(args_path, args_data)
        if path is None:
            continue
        path = path.resolve()
        if path in seen_outputs:
            continue
        seen_outputs.add(path)

        model_name = format_model_name(args_data, args_path.parent.name)
        file_usage, file_warnings = collect_file_usage(path)
        warnings.extend(file_warnings)
        if file_usage.total_text_tokens or include_zero_usage:
            summary[model_name].add_usage(file_usage)

    return dict(summary), warnings


def format_int(value: int) -> str:
    return str(value)


def render_table(summary: dict[str, ModelSummary]) -> str:
    headers = [
        "Model",
        "Runs",
        "Tokens Sent",
        "Tokens Received",
        "Total Tokens",
        "API Calls",
    ]
    table_rows: list[list[str]] = []

    for model_name, stats in sorted(
        summary.items(),
        key=lambda item: (-item[1].total_tokens, item[0]),
    ):
        table_rows.append(
            [
                model_name,
                format_int(stats.runs),
                format_int(stats.tokens_sent),
                format_int(stats.tokens_received),
                format_int(stats.total_tokens),
                format_int(stats.api_calls),
            ]
        )

    widths = [len(header) for header in headers]
    for row in table_rows:
        for index, value in enumerate(row):
            widths[index] = max(widths[index], len(value))

    def format_row(row: list[str]) -> str:
        return "  ".join(value.ljust(widths[index]) for index, value in enumerate(row))

    lines = [format_row(headers), format_row(["-" * width for width in widths])]
    if table_rows:
        lines.extend(format_row(row) for row in table_rows)
    else:
        lines.append("No token usage records found.")

    return "\n".join(lines)


def render_json(summary: dict[str, ModelSummary], base_dir: Path) -> str:
    return json.dumps(
        {
            "base_dir": str(base_dir),
            "models": {
                model_name: asdict(stats)
                for model_name, stats in sorted(summary.items())
            },
        },
        indent=2,
        sort_keys=True,
    )


def main() -> int:
    args = parse_args()
    base_dir = args.base_dir.resolve()

    try:
        summary, warnings = collect_summary(base_dir, args.include_zero_usage)
    except ValueError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 2

    if args.format == "json":
        print(render_json(summary, base_dir))
    else:
        print(render_table(summary))

    for warning in warnings:
        print(f"Warning: {warning}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())

# HWE — Phoenix-bench Code Release

Code that backs the paper *Phoenix-bench: A Hardware Engineering Benchmark for Agentic AI* (NeurIPS 2026). The companion data (per-instance snapshots, full Verilator testbenches, Docker images) lives at the project page; this tree holds source code, scripts, agent run artifacts, and lightweight metadata (~2.2 GB).

All paths and identifiers in this release have been anonymized; absolute paths in scripts and logs point at `/workspace/phoenix-bench/`, which the verifier maps to the snapshot/testbench layout described under "Data NOT included" below.

## Layout

```
HWE/
├── agents/             # the 8 agentic frameworks evaluated in §4.2
│   ├── Agentless/      # workflow-based  (Xia et al. 2024)
│   ├── Aider/          # interactive     (paul-gauthier 2024)
│   ├── ExpeRepair/     # retrieval-aug.  (Mu et al. 2025)
│   ├── KGCompass/      # knowledge-graph (2025)
│   ├── Lingxi/         # multi-agent     (2025)
│   ├── mini-swe-agent/ # minimal SWE-agent variant (2025)
│   ├── OpenHands/      # interactive     (Wang et al. 2024)
│   └── SWE-agent/      # interactive     (Yang et al. 2024)
├── benchmark/
│   ├── construction/   # §3.1 funnel: GitHub crawl → issue/PR filtering
│   ├── verifier/       # §3 Phoenix-Ref harness + gold patches
│   └── eval_harness/   # §4 product+open-source agent evaluation scaffolds
├── rtl_deps/           # RTL libraries needed by some testbenches
│   ├── common_cells/
│   ├── common_verification/
│   ├── pulp_cluster/
│   ├── openhw/  openhw2/
│   └── tech_cells_generic/
└── results/
    ├── eval_patches/   # per-agent generated patches (Tables 3, 4)
    └── openhands_eval/ # OpenHands trajectories used in Fig 5 + Table 5
```

## Mapping to the paper

| Paper element | Code path |
|---|---|
| §3.1 Data collection / 4-stage funnel | `benchmark/construction/` |
| §3 Phoenix-Ref harness (511 instances) | `benchmark/verifier/` |
| §3 Patch complexity / difficulty tiers (Tab 2, App C) | `benchmark/verifier/classify_patch_complexity.py`, `patch_complexity*` |
| §3 F2P / P2P verification | `benchmark/verifier/count_fail_to_pass.{py,sh}`, `f2p_sweep_one.sh` |
| §3 Coverage statistics (Tab 2) | `benchmark/verifier/collect_*coverage*.py` |
| §3 Issue classification (Fig 3) | `benchmark/verifier/classified_issues_full.json`, `classify_missing_issues.py` |
| §4.1 Four product agents | `benchmark/eval_harness/benchmark_{claude,codex,codex_new,copilot,gemini}/` |
| §4.2 Eight open-source agents | `agents/` |
| §4.2 mini-SWE-agent runs | `benchmark/eval_harness/benchmark_mini_agent/` |
| §4.3 File-level oracle localization | `benchmark/eval_harness/benchmark_localizations/` |
| §4.3 Testbench-feedback diagnostic | `results/openhands_eval/`, `benchmark/eval_harness/benchmark_eda/` |
| §4.3 Cross-benchmark drop (Fig 4) | `results/openhands_eval/{hwe,openhands}-trajectories.jsonl` |
| Tab 3 / Tab 4 generated patches | `results/eval_patches/` |

## Data NOT included (download separately)

These are required to actually re-run the benchmark; omitted here for size.

| Artifact | Original location | Size |
|---|---|---|
| Per-instance snapshots (511 × repo HEAD) | `HDL_verified_new/snapshots/` | 21 GB |
| Per-instance Verilator testbenches | `HDL_verified_new/testbench_verilator/` | 16 GB |
| Agent per-instance run dirs (claude/codex/openhands/etc.) | `HDL_agent_eval/benchmark_*/{snapshots,testbench_verilator}/` | 8 × 21 GB |
| OpenHands eval outputs (per-instance logs) | `openhands_eval/benchmarks/eval_outputs/` | 9.5 GB |

`benchmark/verifier/patches/` (122 MB, gold developer patches) IS included — needed for F2P verification once snapshots are restored.

## Reproducing F2P verification

```bash
# After downloading snapshots/ and testbench_verilator/ into benchmark/verifier/
cd benchmark/verifier
ls testbench_verilator/ > /tmp/instances.txt
SWEEP_CSV=/tmp/f2p.csv xargs -P 16 -I {} ./f2p_sweep_one.sh {} < /tmp/instances.txt
```

The included `f2p_full_sweep_2026-05-27.csv` is a snapshot of the 511-instance sweep run on 2026-05-27 (475 PASS / 32 FAIL / 3 ERROR / 1 misclassified).

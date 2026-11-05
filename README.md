# HWE — Phoenix-bench Code Release

Code that backs the paper *Phoenix-bench: A Hardware Engineering Benchmark for Agentic AI* (NeurIPS 2026). The companion data (per-instance snapshots, developer patches, full Verilator testbenches) lives on [Hugging Face](https://huggingface.co/datasets/OvertureMMXXI/Phoenix-Bench); this tree holds source code and scripts.

Absolute paths in the batch scripts point at `/workspace/phoenix-bench/`. Adjust them to your local data location before using those scripts.

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
└── benchmark/
    ├── construction/   # §3.1 funnel: GitHub crawl → issue/PR filtering
    ├── verifier/       # §3 F2P/P2P verifier and analysis scripts
    └── eval_harness/   # §4 Gemini CLI and feedback-run scaffolds
```

## Mapping to the paper

| Paper element | Code path |
|---|---|
| §3.1 Data collection / 4-stage funnel | `benchmark/construction/` |
| §3 Verifier scripts (511 instances) | `benchmark/verifier/` |
| §3 Patch complexity / difficulty tiers (Tab 2, App C) | `benchmark/verifier/classify_patch_complexity.py` |
| §3 F2P / P2P verification | `benchmark/verifier/count_fail_to_pass.{py,sh}`, `f2p_sweep_one.sh` |
| §3 Coverage statistics (Tab 2) | `benchmark/verifier/collect_*coverage*.py` |
| §3 Issue classification (Fig 3) | `benchmark/verifier/classify_missing_issues.py` |
| §4.1 Gemini CLI runs | `benchmark/eval_harness/benchmark_gemini/` |
| §4.2 Eight open-source agents | `agents/` |
| §4.3 Testbench-feedback runs | `benchmark/eval_harness/benchmark_eda/agent_runs/run_and_log.sh` |

## Data (download separately)

The benchmark data is required to re-run verification and is hosted on [Hugging Face](https://huggingface.co/datasets/OvertureMMXXI/Phoenix-Bench):

| Artifact | Dataset path | Size |
|---|---|---|
| Per-instance snapshots (511) | `snapshots/` | 21 GB |
| Per-instance Verilator testbenches | `testbench/` | 16 GB |
| Developer patches | `patches/` | 122 MB |

## Reproducing F2P verification

Install Verilator and Surelog, or set `$OSS_CAD_SUITE` to an OSS CAD Suite installation. Then run one instance from the dataset root:

```bash
bash testbench/AUCOHL_Lighter_pr16/run_verilator.sh
```

The runner checks the buggy and fixed phases and ends with `PASS: <instance>` when the instance fails before the patch and passes after it. Requirements vary by instance.

For batch runs, edit `TB_ROOT` at the top of `benchmark/verifier/f2p_sweep_one.sh` to point at your `testbench/` directory, then run from the dataset root:

```bash
ls testbench/ | grep -v '^_' > /tmp/instances.txt
SWEEP_CSV=/tmp/f2p.csv xargs -P 16 -I {} /path/to/Phoenix-Bench/benchmark/verifier/f2p_sweep_one.sh {} < /tmp/instances.txt
```

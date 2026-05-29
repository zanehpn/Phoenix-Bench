# hw: Fix uncached SPM execute region

Instance: pulp-platform_cheshire_pr189
Source: https://github.com/pulp-platform/cheshire/pull/189
Fetched: 2026-04-26
Repository: pulp-platform/cheshire
Pull request: #189
Author: paulsc96
State: closed
Base branch: main
Head branch: paulsc/spmu-ex
Created: 2025-03-28T11:57:58Z
Updated: 2025-04-13T18:42:51Z
Closed: 2025-04-13T18:42:50Z
Merged: 2025-04-13T18:42:50Z

Fixes #188.

Changes:

* Add uncached SPM as its own executable region (simplify parameterization a bit in the process)
* Add a test `spm_uncached` executing from uncached SPM and verifying it is not cached

Additional changes:

* Add argument to DMA calls to enable dynamic use of decoupling flags (this breaks DMA API compatibility)
* Add `wfi` to default trap handler (this quiets core on exceptions, including on unhandled `ebreak`)

## Local Reproducer Notes

# pulp-platform_cheshire_pr189

Minimal fail-to-pass Verilator case for the uncached SPM execute region fix.

The buggy configuration models cached and uncached SPM as one large executable region. The patch creates an explicit `AmSpmUnc` region and exposes cached and uncached SPM as separate execute rules.

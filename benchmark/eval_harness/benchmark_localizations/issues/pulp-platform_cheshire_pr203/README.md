# treewide: Update iDMA and fix 1D transfers

Instance: pulp-platform_cheshire_pr203
Source: https://github.com/pulp-platform/cheshire/pull/203
Fetched: 2026-04-26
Repository: pulp-platform/cheshire
Pull request: #203
Author: alex96295
State: closed
Base branch: main
Head branch: aottaviano/dma
Created: 2025-05-07T12:48:47Z
Updated: 2025-07-08T20:06:36Z
Closed: 2025-07-08T20:06:35Z
Merged: 2025-07-08T20:06:35Z

* [x] Move DMA to Regbus, simplifying interconnect and fixing a known issue with accessing beyond 32-bit boundary
* [x] Fix DMA HAL for 1D transfers (currently not working)
* [x] Update iDMA
* [x] Add new regression test for 1D transfers to CI (https://iis-git.ee.ethz.ch/pulp-restricted/cheshire-nonfree/-/merge_requests/22)
* [x] Fix #208.
* [x] Add new regression test for accesses beyond 32-bit boundary (access over serial link)

## Local Reproducer Notes

pulp-platform/cheshire PR 203 reproducer.

The reduced RTL models the 1D DMA programming path through the AXI-to-register
adapter.  The buggy snapshot instantiates the legacy adapter, which gates a
valid register write with test mode and drops the one-cycle start command.
The patch switches the wrapper to the v2 adapter interface used by the PR.

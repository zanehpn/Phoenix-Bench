# [hw,pinmux,rtl] Remove sys reset when no strap sampling

Instance: lowRISC_opentitan_pr28469
Source: https://github.com/lowRISC/opentitan/pull/28469
Fetched: 2026-04-26
Repository: lowRISC/opentitan
Pull request: #28469
Author: Razer6
State: closed
Base branch: master
Head branch: pinmux-sys-reset
Created: 2025-10-11T22:52:30Z
Updated: 2025-10-13T14:44:34Z
Closed: 2025-10-13T14:44:33Z
Merged: 2025-10-13T14:44:33Z

The sys reset in pinmux is only needed for the strap sampling logic. Since that feature is gated behind an ipgen parameter, also gate the reset with this flag and remove it for Darjeeling.

Closes https://github.com/lowRISC/opentitan/issues/25410

## Local Reproducer Notes

# lowRISC_opentitan_pr28469

Minimal fail-to-pass Verilator case for removing the sys reset dependency from pinmux strap sampling.

The buggy pinmux clears the sampled strap when `rst_sys_ni` is asserted low even though strap sampling should only depend on the primary reset. The patch ignores the sys reset for the sampled strap state.

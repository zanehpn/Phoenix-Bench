# Fix Summary: pulp-platform/cheshire PR #189 - Uncached SPM Execute Region

## Issue
The buggy configuration modeled cached and uncached SPM as a single combined executable region. This prevented proper distinction between cached and uncached SPM regions.

## Solution
Modified `hw/cheshire_pkg.sv` to split the SPM execute region into separate cached and uncached regions:

### Changes Made:

1. **NrExecuteRegionRules**: Changed from 5 to 6
   - Now accommodates 6 separate execute regions instead of 5

2. **ExecuteRegionAddrBase**: Updated to include explicit uncached SPM region
   - From: `'{AmDbg, AmBrom, AmSpm, 64'h6000_0000, 64'h2000_0000, 64'h0}`
   - To: `'{AmDbg, AmBrom, AmSpm, AmSpmBaseUncached, 64'h6000_0000, 64'h2000_0000}`
   - Now includes AmSpmBaseUncached (0x1400_0000) as a distinct region

3. **ExecuteRegionLength**: Split SPM size between cached and uncached
   - From: `'{64'h40000, 64'h40000, 2 * SizeSpm, 64'h1000_0000, 64'h1000_0000, 64'h0}`
   - To: `'{64'h40000, 64'h40000, SizeSpm, SizeSpm, 64'h1000_0000, 64'h1000_0000}`
   - Each SPM region (cached and uncached) gets SizeSpm length instead of combined 2*SizeSpm

## Execute Regions After Fix:
1. AmDbg (0x0000_0000) - 0x40000 bytes
2. AmBrom (0x0200_0000) - 0x40000 bytes
3. AmSpm (0x1000_0000) - SizeSpm bytes [CACHED SPM]
4. AmSpmBaseUncached (0x1400_0000) - SizeSpm bytes [UNCACHED SPM]
5. Region (0x6000_0000) - 0x1000_0000 bytes
6. Region (0x2000_0000) - 0x1000_0000 bytes

## Logic Impact:
The module's uncached detection (line 68) now correctly identifies addresses in the 0x1400_0000 range as uncached SPM regions, properly setting the `uncached_rule_o` output when execute operations fall within the uncached SPM region.

## Verification:
- Syntax validated with Verilator (no new errors introduced)
- Changes are logically consistent with the PR description
- Backward compatible with existing module structure

### Phase 1: FIX ANALYSIS

1. **Problem summary**

The core is reporting the wrong exception for a misaligned load (`lh x5,0(x5)` with `x5=0xffffffff`) when `ZICCLSM` is **not** enabled.  
Expected (per issue/spec interpretation): **Load Address Misaligned** (cause code 4).  
Observed in Wally: **Load Access Fault** (cause code 5).

This happens because both misaligned and access-fault conditions can be true at once, and access fault is not being suppressed in that case.

2. **Where it occurs**

The issue is in `src/mmu/mmu.sv`, in the fault-generation logic:

- `LoadMisalignedFaultM` / `StoreAmoMisalignedFaultM` are computed correctly.
- But `LoadAccessFaultM` / `StoreAmoAccessFaultM` are also asserted independently, so both can be active simultaneously.

Given downstream trap handling, this can produce the wrong priority outcome.

3. **Best practices for fix**

- Keep the change **minimal** and localized.
- Avoid changing global trap machinery when local fault mutual-exclusion is sufficient.
- Ensure only one fault class is asserted for the same memory operation when priority is architecturally expected.
- Preserve existing special behavior (e.g., misaligned atomics causing access fault under `ZICCLSM` conditions).

4. **Fix approach**

In `mmu.sv`, gate access faults with `~LoadMisalignedFaultM` / `~StoreAmoMisalignedFaultM`.  
This enforces that when a misaligned fault is present, access fault is suppressed, resulting in cause code 4 in the failing scenario.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>src/mmu/mmu.sv</file>
<original>  // Access faults
  // If TLB miss and translating we want to not have faults from the PMA and PMP checkers.
  assign InstrAccessFaultF    = (PMAInstrAccessFaultF    | PMPInstrAccessFaultF)    & ~TLBMiss;
  assign LoadAccessFaultM     = (PMALoadAccessFaultM     | PMPLoadAccessFaultM     | AtomicMisalignedCausesAccessFaultM & ReadNoAmoAccessM)     & ~TLBMiss;
  assign StoreAmoAccessFaultM = (PMAStoreAmoAccessFaultM | PMPStoreAmoAccessFaultM | AtomicMisalignedCausesAccessFaultM & WriteAccessM) & ~TLBMiss;

  // Specify which type of page fault is occurring
  assign InstrPageFaultF    = TLBPageFault & ExecuteAccessF;
  assign LoadPageFaultM     = TLBPageFault & ReadNoAmoAccessM; 
  assign StoreAmoPageFaultM = TLBPageFault & (WriteAccessM | (|CMOpM));</original>
<patched>  // Access faults
  // If TLB miss and translating we want to not have faults from the PMA and PMP checkers.
  // Suppress access faults when a misaligned fault is already present so that misaligned
  // exceptions take priority for the same memory operation.
  assign InstrAccessFaultF    = (PMAInstrAccessFaultF    | PMPInstrAccessFaultF)    & ~TLBMiss;
  assign LoadAccessFaultM     = (PMALoadAccessFaultM     | PMPLoadAccessFaultM     | AtomicMisalignedCausesAccessFaultM & ReadNoAmoAccessM)     & ~TLBMiss & ~LoadMisalignedFaultM;
  assign StoreAmoAccessFaultM = (PMAStoreAmoAccessFaultM | PMPStoreAmoAccessFaultM | AtomicMisalignedCausesAccessFaultM & WriteAccessM) & ~TLBMiss & ~StoreAmoMisalignedFaultM;

  // Specify which type of page fault is occurring
  assign InstrPageFaultF    = TLBPageFault & ExecuteAccessF;
  assign LoadPageFaultM     = TLBPageFault & ReadNoAmoAccessM; 
  assign StoreAmoPageFaultM = TLBPageFault & (WriteAccessM | (|CMOpM));</patched>
```
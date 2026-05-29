### Phase 1: FIX ANALYSIS

1. **Problem summary**

The core is reporting the wrong exception type for a misaligned load in a case where `ZICCLSM` is not enabled.  
For the failing `lh x5,0(x5)` access, both:
- misaligned condition, and
- access fault condition

can become true at the same time.  
Wally ends up taking **Load Access Fault (code 5)**, while expected behavior is **Load Address Misaligned (code 4)**.

2. **Where it occurs**

The issue is in `src/mmu/mmu.sv`, in the fault generation logic:

- `LoadMisalignedFaultM` / `StoreAmoMisalignedFaultM` are generated first.
- `LoadAccessFaultM` / `StoreAmoAccessFaultM` are generated independently and are **not masked** when corresponding misaligned faults are present.

So both signals can be asserted simultaneously, and downstream trap selection can pick the wrong one.

3. **Best practices for the fix**

- Keep change minimal and local to fault classification.
- Preserve existing behavior for atomic misaligned corner case (`AtomicMisalignedCausesAccessFaultM`) when misaligned faults are intentionally suppressed.
- Avoid broader trap-priority rewrites if a local signal-level fix can enforce correct classification.

4. **Fix approach**

Mask access faults when same-class misaligned fault is asserted:
- `LoadAccessFaultM` should be suppressed if `LoadMisalignedFaultM` is active.
- `StoreAmoAccessFaultM` should be suppressed if `StoreAmoMisalignedFaultM` is active.

This guarantees deterministic and spec-aligned exception classification for the reported case.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>src/mmu/mmu.sv</file>
<original>  // Access faults
  // If TLB miss and translating we want to not have faults from the PMA and PMP checkers.
  assign InstrAccessFaultF    = (PMAInstrAccessFaultF    | PMPInstrAccessFaultF)    & ~TLBMiss;
  assign LoadAccessFaultM     = (PMALoadAccessFaultM     | PMPLoadAccessFaultM     | AtomicMisalignedCausesAccessFaultM & ReadNoAmoAccessM)     & ~TLBMiss;
  assign StoreAmoAccessFaultM = (PMAStoreAmoAccessFaultM | PMPStoreAmoAccessFaultM | AtomicMisalignedCausesAccessFaultM & WriteAccessM) & ~TLBMiss;</original>
<patched>  // Access faults
  // If TLB miss and translating we want to not have faults from the PMA and PMP checkers.
  // Also suppress access faults when the corresponding misaligned fault is present so
  // misaligned exceptions take priority for the same memory operation.
  assign InstrAccessFaultF    = (PMAInstrAccessFaultF    | PMPInstrAccessFaultF)    & ~TLBMiss;
  assign LoadAccessFaultM     = (PMALoadAccessFaultM     | PMPLoadAccessFaultM     | AtomicMisalignedCausesAccessFaultM & ReadNoAmoAccessM)     & ~TLBMiss & ~LoadMisalignedFaultM;
  assign StoreAmoAccessFaultM = (PMAStoreAmoAccessFaultM | PMPStoreAmoAccessFaultM | AtomicMisalignedCausesAccessFaultM & WriteAccessM) & ~TLBMiss & ~StoreAmoMisalignedFaultM;</patched>
```
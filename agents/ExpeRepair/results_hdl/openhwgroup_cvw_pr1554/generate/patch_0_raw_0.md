### Phase 1: FIX ANALYSIS

1. **Problem summary**

The core is raising the wrong exception type for a misaligned load (`lh`) when `ZICCLSM` (misaligned load/store support) is not enabled.  
In the failing case, the load address is both:
- **misaligned** (should trigger exception code 4: Load Address Misaligned), and
- in an invalid/forbidden region (can also trigger Load Access Fault).

Wally is currently reporting **Load Access Fault** instead of **Load Address Misaligned**.

---

2. **Where it occurs**

The issue is in `src/mmu/mmu.sv`, in how fault outputs are generated:

- `LoadMisalignedFaultM` / `StoreAmoMisalignedFaultM` are computed correctly.
- But `LoadAccessFaultM` / `StoreAmoAccessFaultM` are also asserted independently from PMA/PMP logic.
- If trap logic prioritizes access fault (or both are high), wrong cause can be observed.

Relevant lines in provided context:

```systemverilog
assign LoadAccessFaultM     = (PMALoadAccessFaultM ... ) & ~TLBMiss;
assign StoreAmoAccessFaultM = (PMAStoreAmoAccessFaultM ... ) & ~TLBMiss;
```

These should be suppressed when misaligned fault is already active (except cases where misaligned is intentionally converted to access fault, already handled by existing `AtomicMisalignedCausesAccessFaultM` logic).

---

3. **Best practices for the fix**

- Keep change minimal and local to fault-generation point.
- Preserve existing atomic special-case behavior.
- Avoid touching tests or unrelated modules.
- Make exception signaling mutually consistent so only the architecturally intended cause is seen.

---

4. **Fix approach**

Gate access faults with the corresponding misaligned fault outputs:

- `LoadAccessFaultM` should be deasserted when `LoadMisalignedFaultM` is asserted.
- `StoreAmoAccessFaultM` should be deasserted when `StoreAmoMisalignedFaultM` is asserted.

This enforces misaligned priority for non-`ZICCLSM` paths while preserving existing behavior for supported misaligned handling and atomic corner cases.

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
  // When misaligned accesses are not handled in hardware, prioritize misaligned exceptions over access faults.
  assign InstrAccessFaultF    = (PMAInstrAccessFaultF    | PMPInstrAccessFaultF)    & ~TLBMiss;
  assign LoadAccessFaultM     = (PMALoadAccessFaultM     | PMPLoadAccessFaultM     | AtomicMisalignedCausesAccessFaultM & ReadNoAmoAccessM)     & ~TLBMiss & ~LoadMisalignedFaultM;
  assign StoreAmoAccessFaultM = (PMAStoreAmoAccessFaultM | PMPStoreAmoAccessFaultM | AtomicMisalignedCausesAccessFaultM & WriteAccessM) & ~TLBMiss & ~StoreAmoMisalignedFaultM;

  // Specify which type of page fault is occurring
  assign InstrPageFaultF    = TLBPageFault & ExecuteAccessF;
  assign LoadPageFaultM     = TLBPageFault & ReadNoAmoAccessM; 
  assign StoreAmoPageFaultM = TLBPageFault & (WriteAccessM | (|CMOpM));</patched>
```
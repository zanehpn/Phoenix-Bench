### Phase 1: FIX ANALYSIS

1. **Problem summary**

The core is raising the wrong exception type when a load/store address is both:
- misaligned, and
- also hits an access-fault condition (PMA/PMP).

In the reported scenario (`lh x5,0(x5)` with `x5 = 0xffffffff`, Zicclsm disabled), Wally reports **Load Access Fault** instead of **Load Address Misaligned** (exception code 4).  
For this project’s expected behavior (and the referenced Priv spec interpretation), misaligned should win here when misaligned accesses are not supported in hardware.

2. **Where it occurs**

The issue is in `src/mmu/mmu.sv` fault generation logic:

- `LoadMisalignedFaultM` / `StoreAmoMisalignedFaultM` are generated.
- `LoadAccessFaultM` / `StoreAmoAccessFaultM` are also generated independently.
- Nothing suppresses access faults when a misaligned fault is already present.

So both can assert simultaneously, and downstream trap priority may choose access fault first, causing the mismatch.

3. **Best practices for fix**

- Keep changes minimal and localized to fault-source generation.
- Avoid changing global trap-priority logic when source masking can enforce intended precedence.
- Preserve existing special-case behavior (e.g., misaligned atomics causing access fault under Zicclsm-supported path).
- Do not alter unrelated modules/tests.

4. **Fix approach**

In `mmu.sv`, mask access faults when corresponding misaligned faults are asserted:

- `LoadAccessFaultM` should be gated by `~LoadMisalignedFaultM`
- `StoreAmoAccessFaultM` should be gated by `~StoreAmoMisalignedFaultM`

This guarantees misaligned exceptions are selected in the conflicting case and resolves the reported mismatch.

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
  // Also suppress access faults when a corresponding misaligned fault is already detected
  // so misaligned exceptions take priority for non-ZICCLSM misaligned accesses.
  assign InstrAccessFaultF    = (PMAInstrAccessFaultF    | PMPInstrAccessFaultF)    & ~TLBMiss;
  assign LoadAccessFaultM     = (PMALoadAccessFaultM     | PMPLoadAccessFaultM     | AtomicMisalignedCausesAccessFaultM & ReadNoAmoAccessM)     & ~TLBMiss & ~LoadMisalignedFaultM;
  assign StoreAmoAccessFaultM = (PMAStoreAmoAccessFaultM | PMPStoreAmoAccessFaultM | AtomicMisalignedCausesAccessFaultM & WriteAccessM) & ~TLBMiss & ~StoreAmoMisalignedFaultM;

  // Specify which type of page fault is occurring
  assign InstrPageFaultF    = TLBPageFault & ExecuteAccessF;
  assign LoadPageFaultM     = TLBPageFault & ReadNoAmoAccessM; 
  assign StoreAmoPageFaultM = TLBPageFault & (WriteAccessM | (|CMOpM));</patched>
```
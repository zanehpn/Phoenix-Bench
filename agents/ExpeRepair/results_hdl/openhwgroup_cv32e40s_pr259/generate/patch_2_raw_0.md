### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue is that after setting `mseccfg.MML=1` (with no PMP entries configured), the core still allows fetching/executing the next instruction in M-mode.  
Per Smepmp, when `MML=1`, executing from an address with **no matching PMP rule** must be denied.

So the bug is a wrong **default permission** for instruction fetch in M-mode when no PMP region matches and `MML=1`.

---

2. **Where it occurs**

The issue is in `rtl/cv32e40s_pmp.sv`, in the **access fault prioritization** default assignment:

```systemverilog
access_fault = csr_pmp_i.mseccfg.mmwp || (priv_lvl_i != PRIV_LVL_M);
```

This default allows unmatched accesses in M-mode when `MMWP=0`, regardless of `MML`.  
Since the fetch path can have no matching region immediately after setting `MML`, instruction fetch incorrectly passes.

---

3. **Best practices for the fix**

- Keep behavior unchanged for non-MML scenarios.
- Apply the narrowest fix: only change default behavior required by spec.
- Let existing region-priority/override logic remain intact.
- Keep combinational logic simple and deterministic.

---

4. **How to fix**

Change default `access_fault` logic so that when:
- `mseccfg.MML=1`, and
- request is instruction fetch (`PMP_ACC_EXEC`),

then default is **deny** (fault) unless a matching PMP region later overrides it.

That means:
- Under `MML + EXEC`, initialize `access_fault = 1'b1`.
- Otherwise, keep existing legacy default (`MMWP || priv!=M`).

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>rtl/cv32e40s_pmp.sv</file>
<original>  // Access fault prioritization
  always_comb begin
    // When MSECCFG.MMWP is set default deny always, otherwise allow for M-mode, deny for other
    // modes
    access_fault = csr_pmp_i.mseccfg.mmwp || (priv_lvl_i != PRIV_LVL_M);

    // PMP entries are statically prioritized, from 0 to N-1
    // The lowest-numbered PMP entry which matches an address determines accessability
    for (int i_r = PMP_NUM_REGIONS-1; i_r >= 0; i_r--) begin
      if (region_match_all[i_r]) begin
        access_fault = access_fault_all[i_r];
      end
    end
  end</original>
<patched>  // Access fault prioritization
  always_comb begin
    // Default access behavior when no PMP region matches:
    // - With MSECCFG.MML set, instruction fetches from unmatched regions are denied.
    // - Otherwise, when MSECCFG.MMWP is set default deny always, else allow for M-mode and deny
    //   for other modes.
    if (csr_pmp_i.mseccfg.mml && (pmp_req_type_i == PMP_ACC_EXEC)) begin
      access_fault = 1'b1;
    end else begin
      access_fault = csr_pmp_i.mseccfg.mmwp || (priv_lvl_i != PRIV_LVL_M);
    end

    // PMP entries are statically prioritized, from 0 to N-1
    // The lowest-numbered PMP entry which matches an address determines accessability
    for (int i_r = PMP_NUM_REGIONS-1; i_r >= 0; i_r--) begin
      if (region_match_all[i_r]) begin
        access_fault = access_fault_all[i_r];
      end
    end
  end</patched>
```
### Phase 1: FIX ANALYSIS

1. **Problem summary**

The core currently allows the next instruction fetch in M-mode right after `mseccfg.MML` is set, when no PMP region matches.  
Per Smepmp, with `MML=1`, **execution from memory without a matching PMP rule must be denied** (and also denied for matching S/U-only rules in M-mode).  
So the default “no matching rule” behavior for instruction fetch is wrong.

---

2. **Where it occurs**

The issue is in **`rtl/cv32e40s_pmp.sv`**, in the access-fault default logic:

```systemverilog
// When MSECCFG.MMWP is set default deny always, otherwise allow for M-mode, deny for other modes
access_fault = csr_pmp_i.mseccfg.mmwp || (priv_lvl_i != PRIV_LVL_M);
```

This default is used when no PMP entry matches.  
With `MML=1`, this still allows M-mode (if `MMWP=0`) for all accesses, including execute, which violates Smepmp execute behavior.

---

3. **Best practices for the fix**

- Keep change **minimal and local** to permission decision logic.
- Do not alter matching priority or per-entry checks unless needed.
- Preserve existing behavior for non-MML cases.
- Add clear comments describing MML/no-match execute behavior.
- Avoid touching unrelated modules or interfaces.

---

4. **How to fix**

Update the default access-fault initialization so that when:
- `mseccfg.MML == 1`, and
- request type is instruction execute (`PMP_ACC_EXEC`),

then access is denied even in M-mode when no region matches.

Concretely, extend default `access_fault` with:
```systemverilog
(csr_pmp_i.mseccfg.mml && (pmp_req_type_i == PMP_ACC_EXEC))
```

This ensures fetch is blocked immediately after enabling MML unless an appropriate PMP rule permits it.

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
    // Default deny policy when no PMP rule matches:
    // - MSECCFG.MMWP set: deny all accesses
    // - S/U mode: deny access
    // - MSECCFG.MML set: deny execute accesses (Smepmp)
    access_fault = csr_pmp_i.mseccfg.mmwp ||
                   (priv_lvl_i != PRIV_LVL_M) ||
                   (csr_pmp_i.mseccfg.mml && (pmp_req_type_i == PMP_ACC_EXEC));

    // PMP entries are statically prioritized, from 0 to N-1
    // The lowest-numbered PMP entry which matches an address determines accessability
    for (int i_r = PMP_NUM_REGIONS-1; i_r >= 0; i_r--) begin
      if (region_match_all[i_r]) begin
        access_fault = access_fault_all[i_r];
      end
    end
  end</patched>
```
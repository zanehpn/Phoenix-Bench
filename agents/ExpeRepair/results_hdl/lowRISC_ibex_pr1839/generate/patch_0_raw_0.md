### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue is a PMP/cosim mismatch for an instruction fetch that straddles a PMP TOR boundary.  
Spike correctly raises **Instruction Access Fault** at `0x80005cc4` (TOR end, exclusive).  
Ibex misses that fault in this scenario.

This happens when a 32-bit instruction starts at a halfword-aligned but word-unaligned address (i.e., instruction straddles two words / two PMP checks are needed).

---

2. **Where the bug is**

The bug is in `rtl/ibex_if_stage.sv`, in PMP error combination logic:

```systemverilog
assign if_instr_pmp_err = pmp_err_if_i |
                          (if_instr_addr[2] & ~instr_is_compressed & pmp_err_if_plus2_i);
...
assign if_instr_err_plus2 = ((if_instr_addr[2] & ~instr_is_compressed & pmp_err_if_plus2_i) |
                             fetch_err_plus2) & ~pmp_err_if_i;
```

For unaligned 32-bit instructions, the relevant indicator is **address bit [1]** (halfword offset), not bit [2].  
Using bit `[2]` causes the second-half PMP check to be skipped for cases like `...cc2 -> ...cc4`, exactly the reported case.

---

3. **Best practices for fix**

- Make the smallest possible functional change in IF-stage error gating.
- Keep behavior unchanged for aligned or compressed instructions.
- Preserve existing priority/masking semantics (`~pmp_err_if_i` logic).
- Avoid touching unrelated modules/tests.

---

4. **Fix approach**

Replace `if_instr_addr[2]` with `if_instr_addr[1]` in the two PMP-plus2 gating expressions:
- `if_instr_pmp_err`
- `if_instr_err_plus2`

This ensures second-half PMP faults are checked whenever a 32-bit instruction is unaligned (straddling boundary), matching Spike behavior.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>rtl/ibex_if_stage.sv</file>
<original>  // PMP errors
  // An error can come from the instruction address, or the next instruction address for unaligned,
  // uncompressed instructions.
  assign if_instr_pmp_err = pmp_err_if_i |
                            (if_instr_addr[2] & ~instr_is_compressed & pmp_err_if_plus2_i);

  // Combine bus errors and pmp errors
  assign if_instr_err = if_instr_bus_err | if_instr_pmp_err;

  // Capture the second half of the address for errors on the second part of an instruction
  assign if_instr_err_plus2 = ((if_instr_addr[2] & ~instr_is_compressed & pmp_err_if_plus2_i) |
                               fetch_err_plus2) & ~pmp_err_if_i;</original>
<patched>  // PMP errors
  // An error can come from the instruction address, or the next instruction address for unaligned,
  // uncompressed instructions.
  assign if_instr_pmp_err = pmp_err_if_i |
                            (if_instr_addr[1] & ~instr_is_compressed & pmp_err_if_plus2_i);

  // Combine bus errors and pmp errors
  assign if_instr_err = if_instr_bus_err | if_instr_pmp_err;

  // Capture the second half of the address for errors on the second part of an instruction
  assign if_instr_err_plus2 = ((if_instr_addr[1] & ~instr_is_compressed & pmp_err_if_plus2_i) |
                               fetch_err_plus2) & ~pmp_err_if_i;</patched>
```
### Phase 1: FIX ANALYSIS

1. **Problem summary**

`MINSTRET` is incrementing for a `DRET` executed while in Machine mode.  
In that case, `DRET` is not legal (it causes an exception), so it must **not** be counted as retired.

2. **Where it happens**

The issue is in `rtl/cve2_id_stage.sv`, in the retire qualification signal:

```systemverilog
assign instr_perf_count_id_o = ~ebrk_insn & ~ecall_insn_dec & ~illegal_insn_dec &
    ~illegal_csr_insn_i & ~instr_fetch_err_i;
```

This excludes decoder-illegal instructions, but not the specific case of `DRET` being illegal outside debug mode (which is determined by controller/debug state, not by `illegal_insn_dec`).

3. **Best practices for the fix**

- Keep the change minimal and local to retirement counting logic.
- Do not alter decode/exception behavior; only correct performance counting qualification.
- Preserve legal `DRET` retirement behavior (when in debug mode).

4. **Fix approach**

Update `instr_perf_count_id_o` to explicitly exclude `DRET` when not in debug mode:

- Add `~(dret_insn_dec & ~debug_mode_o)` into retire qualification.

This prevents false `MINSTRET` increments for exceptioning `DRET` in M-mode while allowing legal `DRET` in debug mode to still count.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>rtl/cve2_id_stage.sv</file>
<original>  // Signal which instructions to count as retired in minstret, all traps along with ebrk and
  // ecall instructions are not counted.
  assign instr_perf_count_id_o = ~ebrk_insn & ~ecall_insn_dec & ~illegal_insn_dec &
      ~illegal_csr_insn_i & ~instr_fetch_err_i;</original>
<patched>  // Signal which instructions to count as retired in minstret, all traps along with ebrk and
  // ecall instructions are not counted.
  // DRET is only legal in debug mode, so do not count it when seen outside debug mode.
  assign instr_perf_count_id_o = ~ebrk_insn & ~ecall_insn_dec & ~illegal_insn_dec &
      ~illegal_csr_insn_i & ~instr_fetch_err_i & ~(dret_insn_dec & ~debug_mode_o);</patched>
```
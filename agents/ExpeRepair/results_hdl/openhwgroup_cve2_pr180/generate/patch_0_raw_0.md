### Phase 1: FIX ANALYSIS

1. **Problem summary**

`MINSTRET` is incrementing when `dret` is executed while **not in debug mode** (e.g. Machine mode).  
In that case, `dret` is illegal and causes an exception, so it is **not retired** and must **not** be counted.

2. **Where the issue occurs**

The issue is in `rtl/cve2_id_stage.sv`, in the logic driving:

```systemverilog
instr_perf_count_id_o
```

Current logic excludes:
- `ebrk`
- `ecall`
- decoded illegal instructions
- illegal CSR instructions
- fetch errors

But it does **not** exclude the `dret`-illegal-by-context case (`dret` when not in debug mode), which is detected by controller state/context rather than basic decode legality.

3. **Best practices for the fix**

- Keep change minimal and localized.
- Do not alter architectural behavior except instruction-retire counting condition.
- Use already-available signals (`dret_insn_dec`, `debug_mode_o`) instead of adding new plumbing.
- Preserve existing counting conditions.

4. **How to fix**

Update `instr_perf_count_id_o` so it also excludes:
- `dret` when `debug_mode_o == 0` (illegal `dret`, not retired).

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
  // Exclude DRET executed outside debug mode as it raises an illegal instruction exception and does
  // not retire.
  assign instr_perf_count_id_o = ~ebrk_insn & ~ecall_insn_dec & ~illegal_insn_dec &
      ~illegal_csr_insn_i & ~instr_fetch_err_i & ~(dret_insn_dec & ~debug_mode_o);</patched>
```
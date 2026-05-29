### Phase 1: FIX ANALYSIS

1. **Problem summary**

`MINSTRET` is incrementing when a `DRET` is executed in **Machine mode**.  
But `DRET` is only legal in debug mode; outside debug mode it causes an illegal-instruction exception and should **not** be counted as retired.

2. **Where it occurs**

The retire-count qualification is in `rtl/cve2_id_stage.sv`:

```systemverilog
assign instr_perf_count_id_o = ~ebrk_insn & ~ecall_insn_dec & ~illegal_insn_dec &
    ~illegal_csr_insn_i & ~instr_fetch_err_i;
```

This logic excludes some traps (`ebrk`, `ecall`, decode-illegal CSR/fetch errors), but it does **not** exclude the specific case of `DRET` executed while not in debug mode.

3. **Best practices for the fix**

- Keep the change minimal and local to performance-count qualification.
- Avoid changing decode/controller exception flow.
- Explicitly gate out known non-retiring illegal special-instruction case (`DRET` outside debug mode).
- Preserve legal `DRET` behavior in debug mode.

4. **Fix approach**

Update `instr_perf_count_id_o` so it is deasserted when:
- `dret_insn_dec` is asserted **and**
- `debug_mode_o` is not set (i.e., `DRET` is illegal and traps).

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
  // DRET only retires in debug mode; outside debug mode it raises an illegal instruction exception
  // and must not increment minstret.
  assign instr_perf_count_id_o = ~ebrk_insn & ~ecall_insn_dec & ~illegal_insn_dec &
      ~illegal_csr_insn_i & ~instr_fetch_err_i & ~(dret_insn_dec & ~debug_mode_o);</patched>
```
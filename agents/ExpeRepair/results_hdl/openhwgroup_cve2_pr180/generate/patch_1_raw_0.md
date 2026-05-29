### Phase 1: FIX ANALYSIS

1. **Problem statement**

`MINSTRET` is being incremented for a `DRET` executed while **not in debug mode** (e.g., Machine mode).  
That `DRET` is illegal and causes an exception, so it is **not retired** and must **not** increment `minstret`.

2. **Where it happens**

The issue is in `rtl/cve2_id_stage.sv`, in the logic that generates `instr_perf_count_id_o`:

```systemverilog
assign instr_perf_count_id_o = ~ebrk_insn & ~ecall_insn_dec & ~illegal_insn_dec &
    ~illegal_csr_insn_i & ~instr_fetch_err_i;
```

This gating excludes several non-retired cases, but it does **not** exclude an illegal `DRET` due to wrong execution context (outside debug mode).  
`illegal_insn_dec` does not cover this mode-dependent illegality.

3. **Best practices for fix**

- Keep the change minimal and local to the retirement/perf-count qualification logic.
- Reuse already-available control/status signals (`dret_insn_dec`, `debug_mode_o`) rather than introducing new pipeline/control wiring.
- Avoid changing behavior of legal `DRET` (executed in debug mode), which should still be counted if retired.

4. **How to fix**

Update `instr_perf_count_id_o` to also suppress counting when `DRET` is decoded while not in debug mode:

- Add condition: `~(dret_insn_dec & ~debug_mode_o)`

This blocks `minstret` increment for illegal `DRET` exceptions while preserving legal `DRET` retirement counting.

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
  // DRET executed outside debug mode causes an illegal instruction exception and must not count.
  assign instr_perf_count_id_o = ~ebrk_insn & ~ecall_insn_dec & ~illegal_insn_dec &
      ~illegal_csr_insn_i & ~instr_fetch_err_i & ~(dret_insn_dec & ~debug_mode_o);</patched>
```


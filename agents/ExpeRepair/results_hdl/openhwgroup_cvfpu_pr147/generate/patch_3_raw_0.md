### Phase 1: FIX ANALYSIS

1. **Problem statement**

The issue is a wrong sign result in `fcvt.w.d` for negative double inputs at the signed 32-bit boundary (`-2^31` case and related saturation/min-int behavior).  
You observed:

- `rounded_abs = 0xffffffff80000000` (already negative/sign-extended form)
- `rounded_sign = 1`
- Current logic does: `-rounded_abs`, producing `0x0000000080000000` (wrong for signed `W` result)

So the sign is effectively applied **twice** in this corner case.

2. **Where it occurs**

The bug is at the integer sign-application assignment in `src/fpnew_cast_multi.sv`:

```systemverilog
assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;
```

This assumes `rounded_abs` is always a pure magnitude. But in min-int/sign-extended edge cases it may already be in final signed form.

3. **Best practices for the fix**

- Keep fix minimal and local to the sign-application step.
- Preserve existing behavior for normal cases.
- Handle both representations robustly:
  - if `rounded_abs` is magnitude → negate when sign is set
  - if `rounded_abs` is already sign-extended signed value → do not negate again
- Avoid changing pipeline/control/dataflow beyond necessary.

4. **How to fix**

Gate negation so it is skipped when converting to **signed int** and `rounded_abs` is already negative in full internal width (`MSB=1`).  
For unsigned conversions (`op_mod_q2==1`), keep previous behavior.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>src/fpnew_cast_multi.sv</file>
<original>assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;</original>
<patched>assign rounded_int_res = (rounded_sign && (op_mod_q2 || ~rounded_abs[MAX_INT_WIDTH-1]))
      ? unsigned'(-rounded_abs) : rounded_abs;</patched>
```


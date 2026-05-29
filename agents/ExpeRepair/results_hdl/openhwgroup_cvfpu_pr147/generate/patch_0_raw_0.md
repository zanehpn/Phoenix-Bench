### Phase 1: FIX ANALYSIS

1. **Problem summary**

The failing case is `fcvt.w.d` with input `0xC1E0000000000000` (i.e. `-2^31`), where the expected RV64 result is `0xffffffff80000000`.

The logic currently does:

```systemverilog
assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;
```

This is intended to apply the sign to an **absolute** rounded integer (`rounded_abs`).  
However, in this edge case, `rounded_abs` is already represented as a signed/extended negative (`0xffffffff80000000`). Negating it again produces `0x0000000080000000`, i.e. the observed wrong value.

---

2. **Where it occurs**

In `src/fpnew_cast_multi.sv`, at the sign-application step that computes `rounded_int_res` from `rounded_abs` and `rounded_sign`.

---

3. **Best practices for the fix**

- Keep the fix **minimal** and local.
- Preserve existing behavior for normal negative values (where `rounded_abs` is truly absolute).
- Avoid double-negation for already signed-extended negative forms (including INT min edge).
- Do not alter unrelated datapath logic or interfaces.

---

4. **Fix approach**

Gate the negation with an MSB check:
- If sign is negative **and** `rounded_abs` is not already negative in container width, negate it.
- Otherwise, pass `rounded_abs` through.

This prevents the erroneous second negation in the reported case while preserving normal behavior.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>src/fpnew_cast_multi.sv</file>
<original>assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;</original>
<patched>assign rounded_int_res = (rounded_sign && !rounded_abs[MAX_INT_WIDTH-1])
                           ? unsigned'(-rounded_abs)
                           : rounded_abs;</patched>
```
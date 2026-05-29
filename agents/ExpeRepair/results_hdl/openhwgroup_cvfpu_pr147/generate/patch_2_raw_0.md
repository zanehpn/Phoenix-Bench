### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue is in `fcvt.w.d` for a negative FP64 input at the signed 32-bit minimum boundary (`-2^31`).

- Expected RV64 result: `0xffffffff80000000` (sign-extended 32-bit `0x80000000`)
- Observed intermediate:
  - `rounded_abs = 0xffffffff80000000`
  - `rounded_sign = 1`
  - current logic computes `rounded_int_res = -rounded_abs = 0x0000000080000000` (wrong for RV64 signed result)

So the sign is effectively applied **twice** in this corner case.

2. **Where the problem is**

In `src/fpnew_cast_multi.sv`, at:
```systemverilog
assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;
```

This line is generally meant to apply the sign after rounding an absolute magnitude.  
However, in this corner case, `rounded_abs` is already in sign-extended minimum-integer form, and negating it flips it incorrectly.

3. **Best practices for the fix**

- Keep change minimal and local.
- Preserve existing behavior for all normal signed/unsigned conversions.
- Handle only the special case where `rounded_abs` is already the sign-extended signed minimum integer for the selected `int_fmt`.
- Avoid broad refactors.

4. **Fix approach**

Gate the negation:
- If conversion is **signed** (`~op_mod_q2`) and `rounded_abs` already equals sign-extended signed-min-int for `int_fmt_q2`, do **not** negate.
- Otherwise keep existing behavior.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>src/fpnew_cast_multi.sv</file>
<original>assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;</original>
<patched>assign rounded_int_res = (rounded_sign &&
                            !(~op_mod_q2 &&
                              (rounded_abs == ({MAX_INT_WIDTH{1'b1}}
                                               << (fpnew_pkg::int_width(int_fmt_q2)-1)))))
                         ? unsigned'(-rounded_abs) : rounded_abs;</patched>
```


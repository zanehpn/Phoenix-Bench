### Phase 1: FIX ANALYSIS

1. **Problem summary**

`fcvt.w.d` for a negative FP64 input at the signed 32-bit minimum edge (`-2^31`) produces a wrong intermediate integer sign application:

- Expected: `0xffffffff80000000`
- Observed: `0x0000000080000000`

The problematic behavior is in:
```systemverilog
assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;
```
This applies a negation unconditionally when `rounded_sign=1`, even in edge cases where `rounded_abs` is already effectively in two’s-complement/sign-extended form for the target signed integer boundary.

2. **Where it occurs**

In `src/fpnew_cast_multi.sv`, at the final sign-application step for float-to-int rounded result (`rounded_int_res` assignment).

3. **Best practices for the fix**

- Keep the fix minimal and local to final sign application.
- Preserve behavior for all normal negative values.
- Avoid changing rounding/normalization pipeline behavior.
- Handle signed-min edge case safely without impacting unsigned conversions.

4. **Fix approach**

Guard the negation for signed conversions so that if `rounded_abs` is already negative in full-width representation (MSB set), it is passed through directly instead of being negated again.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>src/fpnew_cast_multi.sv</file>
<original>assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;</original>
<patched>assign rounded_int_res = (rounded_sign && !op_mod_q2 && rounded_abs[MAX_INT_WIDTH-1]) ? rounded_abs
                                                                                                  : (rounded_sign ? unsigned'(-rounded_abs)
                                                                                                                  : rounded_abs);</patched>
```
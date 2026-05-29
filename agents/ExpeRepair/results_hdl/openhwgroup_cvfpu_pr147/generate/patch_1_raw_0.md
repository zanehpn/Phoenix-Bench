### Phase 1: FIX ANALYSIS

1. **Problem summary**

`fcvt.w.d` for a negative FP64 input (`0xC1E0000000000000`, i.e. `-2^31`) produces a wrong intermediate signed-integer reconstruction:
- expected signed 64-bit representation: `0xFFFFFFFF80000000`
- observed `rounded_int_res`: `0x0000000080000000`

This indicates the sign re-application step is incorrectly handling an already width-extended value.

2. **Where it occurs**

In `src/fpnew_cast_multi.sv`, at the signed integer reconstruction step:

```systemverilog
assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;
```

That expression assumes `rounded_abs` is a pure magnitude.  
For edge cases (like `-2^31` in `fcvt.w.d`), `rounded_abs` can already carry upper-bit extension for the selected integer format, so directly negating it can flip into the wrong representation.

3. **Best practices for the fix**

- Apply sign conversion only on the **active destination integer width** (`int_fmt_q2`), not on potentially pre-extended upper bits.
- Keep change minimal and local.
- Avoid altering rounding/classification logic, pipeline logic, or exception handling.

4. **Fix approach**

Mask `rounded_abs` to the selected integer destination width before optional two’s-complement negation.  
This guarantees consistent behavior for INT8/16/32/64 and fixes the `fcvt.w.d` negative edge case.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>src/fpnew_cast_multi.sv</file>
<original>assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;</original>
<patched>assign rounded_int_res = rounded_sign
      ? unsigned'(-(rounded_abs & ({MAX_INT_WIDTH{1'b1}} >>
                                   (MAX_INT_WIDTH - fpnew_pkg::int_width(int_fmt_q2)))))
      :            (rounded_abs & ({MAX_INT_WIDTH{1'b1}} >>
                                   (MAX_INT_WIDTH - fpnew_pkg::int_width(int_fmt_q2))));</patched>
```


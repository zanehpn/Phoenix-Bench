### Phase 1: FIX ANALYSIS

1. **Problem summary**

The reported failure is for `fcvt.w.d` with a negative FP64 input corresponding to `-2^31`.  
The conversion path computes:

- `rounded_sign = 1` (correct)
- `rounded_abs = 0xffffffff80000000` (this is **not** a pure absolute magnitude; it is sign-extended)
- then applies:
  ```systemverilog
  assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;
  ```
  which negates an already sign-extended value and flips it to `0x0000000080000000` (wrong sign in RV64 sign-extended representation).

So the issue is a **double-signing effect** caused by using `rounded_abs` as if it were always zero-extended magnitude.

2. **Where it occurs**

In `src/fpnew_cast_multi.sv`, at the final integer sign-application step:
```systemverilog
assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;
```

3. **Best practices for fix**

- Keep arithmetic semantics explicit: apply sign only to a **canonical unsigned magnitude**.
- Avoid relying on implicit sign-extension state from earlier narrowing/packing.
- Keep change minimal and local to final sign-application logic.
- Make the fix format-width aware (INT8/16/32/64 via `int_fmt_q2`).

4. **Fix approach**

Before applying `rounded_sign`, normalize `rounded_abs` into a zero-extended value within `MAX_INT_WIDTH` by stripping any upper sign-extension bits according to selected integer width (`int_fmt_q2`).  
Then apply negation only on this normalized magnitude.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>src/fpnew_cast_multi.sv</file>
<original>assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;</original>
<patched>logic [$clog2(MAX_INT_WIDTH+1)-1:0] rounded_abs_shamt;
  logic [MAX_INT_WIDTH-1:0]        rounded_abs_zext;

  // rounded_abs can carry sign-extension from narrow integer formatting.
  // Normalize it to a true zero-extended magnitude before applying sign.
  assign rounded_abs_shamt = unsigned'(MAX_INT_WIDTH - fpnew_pkg::int_width(int_fmt_q2));
  assign rounded_abs_zext  = (rounded_abs << rounded_abs_shamt) >> rounded_abs_shamt;

  assign rounded_int_res   = rounded_sign ? unsigned'(-rounded_abs_zext) : rounded_abs_zext;</patched>
```


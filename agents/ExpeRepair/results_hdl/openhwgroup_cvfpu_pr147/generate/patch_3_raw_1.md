### Phase 1: FIX ANALYSIS

1. **Problem summary**

The reported failure is on `fcvt.w.d` for input `0xC1E0000000000000` (`-2147483648.0`).

- Expected (RV64 sign-extended 32-bit signed result): `0xFFFFFFFF80000000`
- Observed intermediate:
  - `rounded_abs = 0xFFFFFFFF80000000`
  - `rounded_sign = 1`
  - `rounded_int_res = 0x0000000080000000` (wrong)

The problematic line is:

```systemverilog
assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;
```

This line is intended to apply sign after rounding an absolute value.  
However, in this corner case (`-2^(N-1)` for signed target width), `rounded_abs` is already effectively represented with sign-extension in `MAX_INT_WIDTH`, so negating it again flips it incorrectly.

---

2. **Where the problem occurs**

In `src/fpnew_cast_multi.sv`, in the integer result post-rounding/sign-application path (the `rounded_abs` / `rounded_int_res` logic).

---

3. **Best practices for the fix**

- Keep behavior unchanged for normal values.
- Handle all integer destination widths (INT8/16/32/64) without hardcoding per-case if avoidable.
- Apply sign only after constraining value to the selected integer width.
- Keep patch minimal and localized.

---

4. **How to fix**

Before applying `-rounded_abs`, mask `rounded_abs` down to the active integer width (`int_fmt_q2`).  
Then apply sign to that masked value:

- prevents double-sign artifacts on `-2^(N-1)` corner values,
- preserves existing behavior for all other cases.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>src/fpnew_cast_multi.sv</file>
<original>  logic [1:0] fp_round_sticky_bits, int_round_sticky_bits, round_sticky_bits;
  logic       of_before_round, uf_before_round;</original>
<patched>  logic [1:0] fp_round_sticky_bits, int_round_sticky_bits, round_sticky_bits;
  logic       of_before_round, uf_before_round;
  logic [MAX_INT_WIDTH-1:0] rounded_abs_masked; // abs value limited to selected int width</patched>
```

# modification 2
```xml
<file>src/fpnew_cast_multi.sv</file>
<original>assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs) : rounded_abs;</original>
<patched>// Constrain rounded_abs to the selected destination integer width before sign application.
  // This avoids incorrect inversion for edge values like -2^(N-1) when represented in MAX_INT_WIDTH.
  assign rounded_abs_masked = rounded_abs &
      ({MAX_INT_WIDTH{1'b1}} >> (MAX_INT_WIDTH - fpnew_pkg::int_width(int_fmt_q2)));
  assign rounded_int_res = rounded_sign ? unsigned'(-rounded_abs_masked) : rounded_abs_masked;</patched>
```
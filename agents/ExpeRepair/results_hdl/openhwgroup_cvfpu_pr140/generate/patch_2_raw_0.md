## Phase 1: FIX ANALYSIS

### 1) What the problem is

The bug is that `CVFPU` incorrectly raises the `NX` (inexact) flag for floating-point-to-floating-point (`F2F`) conversions when the source value is infinity.

According to IEEE 754, converting infinity between floating-point formats should not, by itself, signal inexact.  
But in the current implementation, infinity ends up producing sticky bits, and those sticky bits cause `NX` to be set.

---

### 2) Where the problem occurs

The issue is in `src/fpnew_cast_multi.sv`, in the floating-point cast path:

- `preshift_mant` is initialized from the input mantissa.
- For infinity, it is set to all ones.
- That value is then shifted and later reduced into `fp_round_sticky_bits`.
- Finally, `fp_regular_status.NX` is computed using `(| fp_round_sticky_bits)`, so the infinity case incorrectly sets `NX`.

The most relevant lines are:

- `preshift_mant = '1;` for infinity / overflow handling
- `assign fp_regular_status.NX = ... (| fp_round_sticky_bits) ...`
- `assign fp_round_sticky_bits[0] = (| {destination_mant[NUM_FP_STICKY-1:0]});`

The core problem is not the sticky-bit extraction itself in general, but the fact that the special infinity case is allowed to contribute sticky bits that later drive `NX`.

---

### 3) Best practices to consider

- Preserve IEEE 754 behavior for infinity conversions.
- Make the fix as localized as possible.
- Avoid changing unrelated rounding behavior for normal finite values.
- Ensure the `NX` flag is suppressed only for infinity-based `F2F` conversions, without affecting overflow handling for finite inputs.
- Prefer gating the status computation rather than rewriting the mantissa/rounding datapath unless necessary.

---

### 4) How to fix it

The cleanest fix is to suppress `NX` for floating-point destination conversions when the source is infinity.

In practice, adjust the `fp_regular_status.NX` assignment so that the inexact flag is only raised when:

- there are sticky bits **and**
- the source is not infinity

This can be done by adding `~info_q.is_inf` to the `NX` condition for the floating-point path.

This keeps existing behavior for normal rounding and overflow cases, while ensuring infinity conversion does not spuriously set `NX`.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>src/fpnew_cast_multi.sv</file>
<original>assign fp_regular_status.NX = src_is_int_q ? (| fp_round_sticky_bits) // overflow is invalid in i2f
            : (| fp_round_sticky_bits) | (~info_q.is_inf & (of_before_round | of_after_round));
</original>
<patched>assign fp_regular_status.NX = src_is_int_q ? (| fp_round_sticky_bits) // overflow is invalid in i2f
            : (~info_q.is_inf & ((| fp_round_sticky_bits) | (of_before_round | of_after_round)));
</patched>
```


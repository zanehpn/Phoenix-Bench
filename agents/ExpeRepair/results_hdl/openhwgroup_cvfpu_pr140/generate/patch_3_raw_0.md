## Phase 1: FIX ANALYSIS

### 1) What the problem is
The bug is that `CVFPU` incorrectly raises the IEEE-754 `NX` (inexact) flag for `F2F` conversions when the source value is infinity.

According to IEEE 754, converting infinity to a floating-point value should not set inexact.  
However, the implementation currently marks the conversion as inexact because the rounding/sticky logic treats infinity like a shifted finite value with all sticky bits set.

### 2) Where the problem occurs
The issue is in `src/fpnew_cast_multi.sv`, in the floating-point cast path:

- **Location #1**: `preshift_mant` is set to `'1` when the source is infinity.
- **Location #2**: sticky bits are derived from `destination_mant`, which is computed from `preshift_mant`.
- **Location #3**: `fp_regular_status.NX` is currently asserted whenever `|fp_round_sticky_bits` is true, even for infinity conversions.

The key root cause is that the special handling for infinity in the overflow path sets `preshift_mant = '1`, which then causes sticky bits to become nonzero, and those sticky bits directly feed `NX`.

### 3) Best practices to take into account
- Preserve IEEE-754 behavior for special values, especially infinities.
- Keep the fix minimal and local to the status/rounding logic.
- Avoid changing unrelated rounding behavior for finite overflow/underflow cases.
- Ensure `NX` is based on actual inexactness, not artifacts of special-value encoding.
- Do not disturb existing overflow/underflow handling beyond the infinity exception behavior.

### 4) How to fix the problem
The best fix is to suppress `NX` for floating-point casts when the source is infinity, regardless of sticky bits.

Concretely:
- Keep the existing overflow/rounding logic intact.
- Modify `fp_regular_status.NX` so that it does **not** assert `NX` when `info_q.is_inf` is true.
- This ensures infinity conversions do not incorrectly signal inexact, even though sticky bits may still be set internally.

A minimal and correct formulation is:

- For `src_is_int_q`: keep current behavior.
- For floating-point sources: `NX = (~info_q.is_inf) & ((|fp_round_sticky_bits) | (~info_q.is_inf & (of_before_round | of_after_round)))`, or equivalently simplify to ensure the entire expression is gated off when `info_q.is_inf`.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>src/fpnew_cast_multi.sv</file>
<original>
  assign fp_regular_status.NV = src_is_int_q & (of_before_round | of_after_round); // overflow is invalid for I2F casts
  assign fp_regular_status.DZ = 1'b0; // no divisions
  assign fp_regular_status.OF = ~src_is_int_q & (~info_q.is_inf & (of_before_round | of_after_round)); // inf casts no OF
  assign fp_regular_status.UF = uf_after_round & fp_regular_status.NX;
  assign fp_regular_status.NX = src_is_int_q ? (| fp_round_sticky_bits) // overflow is invalid in i2f
            : (| fp_round_sticky_bits) | (~info_q.is_inf & (of_before_round | of_after_round));
</original>
<patched>
  assign fp_regular_status.NV = src_is_int_q & (of_before_round | of_after_round); // overflow is invalid for I2F casts
  assign fp_regular_status.DZ = 1'b0; // no divisions
  assign fp_regular_status.OF = ~src_is_int_q & (~info_q.is_inf & (of_before_round | of_after_round)); // inf casts no OF
  assign fp_regular_status.UF = uf_after_round & fp_regular_status.NX;
  assign fp_regular_status.NX = src_is_int_q ? (| fp_round_sticky_bits) // overflow is invalid in i2f
            : (~info_q.is_inf) & ((| fp_round_sticky_bits) | (of_before_round | of_after_round));
</patched>
```


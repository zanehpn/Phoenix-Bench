## Phase 1: FIX ANALYSIS

### 1) What the problem is
The bug is that `CVFPU` incorrectly raises the `NX` (inexact) flag for `F2F` conversions when the source value is infinity.

Per IEEE 754, converting infinity to another floating-point format should not, by itself, be considered inexact. However, the current logic still produces sticky bits for infinity, and those sticky bits cause `NX` to be asserted.

### 2) Where the problem occurs
The issue occurs in `src/fpnew_cast_multi.sv` in the floating-point cast path:

- In the overflow / infinity handling block, `preshift_mant` is set to `'1` for infinity:
  - This makes the mantissa and sticky-related bits all ones.
- Later, `fp_round_sticky_bits` are derived from `destination_mant`, which comes from `preshift_mant`.
- Finally, `fp_regular_status.NX` is computed from `fp_round_sticky_bits`, so infinity ends up setting `NX`.

The key problematic location is:

- `fp_regular_status.NX = src_is_int_q ? ... : (| fp_round_sticky_bits) | (~info_q.is_inf & (of_before_round | of_after_round));`

This expression still uses `( | fp_round_sticky_bits )` even when the source is infinity.

### 3) Best practices to take into account
- Preserve IEEE 754 semantics: infinity conversion should not signal inexact solely because of the special handling path.
- Make the fix minimal and localized to the status generation logic.
- Avoid changing the mantissa/rounding datapath unless necessary; the status flag logic is the correct place to fix this.
- Keep behavior for real overflow/rounding unchanged for non-infinite values.

### 4) How to fix the problem
Update the `NX` generation for floating-point destination results so that infinity suppresses inexact exactly like overflow already suppresses `OF`.

In other words:
- For `F2F` casts, `NX` should be asserted only when:
  - the value is not infinity, and
  - either rounding sticky bits indicate inexactness, or overflow/underflow conditions require it.
- Specifically, gate the `fp_round_sticky_bits` contribution with `~info_q.is_inf`.

This avoids reporting `NX` for infinity while preserving current behavior for all other cases.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>src/fpnew_cast_multi.sv</file>
<original>
assign fp_regular_status.NX = src_is_int_q ? (| fp_round_sticky_bits) // overflow is invalid in i2f
            : (| fp_round_sticky_bits) | (~info_q.is_inf & (of_before_round | of_after_round));
</original>
<patched>
assign fp_regular_status.NX = src_is_int_q ? (| fp_round_sticky_bits) // overflow is invalid in i2f
            : (~info_q.is_inf & ((| fp_round_sticky_bits) | (of_before_round | of_after_round)));
</patched>
```


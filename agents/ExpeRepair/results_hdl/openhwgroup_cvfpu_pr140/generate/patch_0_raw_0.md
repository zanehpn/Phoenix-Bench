### Phase 1: FIX ANALYSIS

#### 1. What the problem is
The bug is that `CVFPU` incorrectly raises the IEEE-754 inexact flag (`NX`) when converting an infinity with `F2F` casts.

Per IEEE 754, converting infinity to another floating-point format should not, by itself, signal inexact.  
However, the current implementation still computes `NX` from sticky bits derived from the mantissa path, and those sticky bits become set for infinity because the mantissa is filled with all `1`s during special handling.

#### 2. Where the problem occurs
The issue is in `src/fpnew_cast_multi.sv`:

- **Location #1**: infinity handling sets:
  - `final_exp`
  - `preshift_mant = '1`
  - `of_before_round = 1'b1`

- **Location #2**: `fp_round_sticky_bits` are derived from `destination_mant`, which is computed from `preshift_mant`. Since `preshift_mant` is all ones for infinity, the sticky bits become nonzero.

- **Location #3**: `fp_regular_status.NX` is computed as:
  - `(| fp_round_sticky_bits)` OR overflow conditions  
  But for infinity, `| fp_round_sticky_bits` is already true, so `NX` is asserted incorrectly even when overflow should be suppressed for infinity.

#### 3. Best practices to take into account
- Preserve IEEE-754 semantics: infinity-to-float conversions should not signal inexact unless there is a real rounding loss.
- Keep the fix minimal and local to status generation logic.
- Avoid changing the mantissa/sticky-bit generation path unless necessary, since it may be shared by other rounding cases.
- Ensure the existing overflow suppression for infinity remains intact.
- Do not alter unrelated integer conversion behavior.

#### 4. How to fix the problem
The cleanest fix is to suppress `NX` for floating-point-to-floating-point conversions when the source is infinity.

Since the code already suppresses `OF` for infinity via `~info_q.is_inf`, `NX` should similarly ignore sticky bits when `info_q.is_inf` is true in the FP destination path.

A minimal fix is to change:

```systemverilog
assign fp_regular_status.NX = src_is_int_q ? (| fp_round_sticky_bits)
            : (| fp_round_sticky_bits) | (~info_q.is_inf & (of_before_round | of_after_round));
```

to make the floating-point path also suppress `NX` on infinity, e.g. by masking sticky-bit-based inexact reporting when `info_q.is_inf` is true.

---

### Phase 2: FIX IMPLEMENTATION

```text
<file>src/fpnew_cast_multi.sv</file>
<original>assign fp_regular_status.NX = src_is_int_q ? (| fp_round_sticky_bits) // overflow is invalid in i2f
            : (| fp_round_sticky_bits) | (~info_q.is_inf & (of_before_round | of_after_round));</original>
<patched>assign fp_regular_status.NX = src_is_int_q ? (| fp_round_sticky_bits) // overflow is invalid in i2f
            : (~info_q.is_inf & (| fp_round_sticky_bits | (of_before_round | of_after_round)));</patched>
```


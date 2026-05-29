## Phase 1: FIX ANALYSIS

### 1) What the problem is
The bug is in the `I2F` conversion path of `cvfpu`: when converting an integer to a floating-point value, overflow is being handled incorrectly.

According to IEEE 754, if the integer value cannot be represented exactly in the target floating-point format after rounding, the conversion should signal **overflow** (`OF`) and typically also **inexact** (`NX`), not **invalid** (`NV`).

In the current implementation, the code treats integer-to-float overflow as invalid and suppresses the overflow flag.

### 2) Where the problem occurs
The issue is in `src/fpnew_cast_multi.sv`, in the status flag generation for floating-point results:

- `fp_regular_status.NV` is set for `src_is_int_q & (of_before_round | of_after_round)`
- `fp_regular_status.OF` is explicitly suppressed for integer sources with `~src_is_int_q`
- `fp_regular_status.NX` also has a special integer-source path with a comment stating overflow is invalid in i2f

The problematic logic is in the block around:
- `fp_regular_status.NV`
- `fp_regular_status.OF`
- `fp_regular_status.NX`

### 3) Best practices to take into account
- Follow IEEE 754 exception semantics:
  - `I2F` overflow should raise `OF`, not `NV`.
  - `NV` is for invalid operations, not for representable-range overflow in integer-to-float conversion.
- Keep the fix minimal and localized.
- Preserve existing behavior for:
  - float-to-float conversions
  - float-to-int conversions
  - NaN / Inf special cases
- Maintain the intended `NX` behavior for inexact conversion, including overflow cases.
- Avoid changing unrelated special-case handling unless necessary.

### 4) How to fix the problem
Update the status flag assignment for floating-point destination conversions so that:

- `OF` is asserted whenever overflow occurs, regardless of whether the source is integer or floating-point.
- `NV` is no longer used for integer-source overflow in `I2F`.
- `NX` remains asserted for rounding/overflow situations as appropriate.

In practice, the minimal fix is to remove the integer-source condition from `NV` and let `OF` reflect overflow consistently.

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
assign fp_regular_status.NV = 1'b0;
assign fp_regular_status.DZ = 1'b0; // no divisions
assign fp_regular_status.OF = ~info_q.is_inf & (of_before_round | of_after_round);
assign fp_regular_status.UF = uf_after_round & fp_regular_status.NX;
assign fp_regular_status.NX = (| fp_round_sticky_bits) | (~info_q.is_inf & (of_before_round | of_after_round));
</patched>
```


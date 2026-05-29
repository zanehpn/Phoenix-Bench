## Phase 1: FIX ANALYSIS

### 1) What the problem is
The issue is that `CVFPU` handles integer-to-floating-point conversions (`I2F`) incorrectly when the integer value cannot be represented exactly in the destination floating-point format.

According to IEEE 754, this situation should raise **overflow** (`OF`) for floating-point results.  
However, the current implementation suppresses `OF` for `I2F` and instead sets **invalid** (`NV`), which is not correct for this case.

This behavior is especially relevant for **half precision**, where some integer values may overflow the representable range. For single and double precision, this usually cannot happen for 32-bit/64-bit integer widths.

### 2) Where the problem occurs
The problematic logic is in:

- `src/fpnew_cast_multi.sv`
- specifically in the `fp_regular_status` assignments around the result selection logic

The key lines are:

```systemverilog
assign fp_regular_status.NV = src_is_int_q & (of_before_round | of_after_round); // overflow is invalid for I2F casts
assign fp_regular_status.OF = ~src_is_int_q & (~info_q.is_inf & (of_before_round | of_after_round)); // inf casts no OF
assign fp_regular_status.NX = src_is_int_q ? (| fp_round_sticky_bits) // overflow is invalid in i2f
          : (| fp_round_sticky_bits) | (~info_q.is_inf & (of_before_round | of_after_round));
```

These comments and assignments show the bug:
- `I2F` overflow is incorrectly mapped to `NV`
- `OF` is explicitly suppressed for integer sources
- `NX` logic is also inconsistent with correct overflow handling for `I2F`

### 3) Best practices to take into account
- Follow IEEE 754 exception semantics:
  - `I2F` overflow should set `OF`
  - It should not be treated as `NV`
- Keep the fix minimal and localized
- Preserve existing behavior for other conversion paths:
  - floating-point to floating-point
  - floating-point to integer
  - special cases already handled elsewhere
- Avoid changing unrelated special-case handling unless necessary
- Keep flags coherent:
  - overflow should also imply inexact in the usual floating-point conversion case
- Maintain style and structure of the existing code

### 4) How to fix the problem
The fix should be applied in `src/fpnew_cast_multi.sv` where `fp_regular_status` is assembled.

The correct behavior is:
- remove the `NV` assignment for integer-source overflow
- allow `OF` to be asserted for `I2F` overflow
- keep `NX` consistent with overflow handling

In practice, the fix is to change the status flag logic so that:
- `OF` is asserted when overflow occurs during `I2F`
- `NV` is not asserted for that case
- `NX` still reflects inexact/overflow as appropriate

---

## Phase 2: FIX IMPLEMENTATION

```patch
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
assign fp_regular_status.OF = ~info_q.is_inf & (of_before_round | of_after_round); // inf casts no OF
assign fp_regular_status.UF = uf_after_round & fp_regular_status.NX;
assign fp_regular_status.NX = (| fp_round_sticky_bits) | (~info_q.is_inf & (of_before_round | of_after_round));
</patched>
```


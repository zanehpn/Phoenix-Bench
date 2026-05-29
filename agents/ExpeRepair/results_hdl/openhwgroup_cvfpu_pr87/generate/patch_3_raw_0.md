## Phase 1: FIX ANALYSIS

### 1. Problem summary
The bug is in `fpnew_opgroup_multifmt_slice`: when slicing operands for each lane, it always uses the bit width of `src_fmt_i` for **all** operands.  
That is correct for operands 0 and 1, but **incorrect for operand 2** in the `ADDMUL` opgroup, because operand 2 and the result use the `dst_fmt_i` format.

As a result, `operands_i[2]` is split incorrectly across lanes whenever `src_fmt_i` and `dst_fmt_i` differ.

### 2. Where the problem occurs
The issue is in:

- `src/fpnew_opgroup_multifmt_slice.sv`

Specifically this code:

```systemverilog
always_comb begin : prepare_input
  for (int unsigned i = 0; i < NUM_OPERANDS; i++) begin
    local_operands[i] = operands_i[i] >> LANE*fpnew_pkg::fp_width(src_fmt_i);
  end
```

This applies `fp_width(src_fmt_i)` to operand 2 as well.

### 3. Best practices to take into account
- Make the smallest possible fix.
- Preserve existing behavior for operands 0 and 1.
- Ensure the third operand uses `dst_fmt_i` only where architecturally required.
- Avoid changing unrelated logic, especially conversion handling and special cases.
- Keep the fix local to the operand slicing logic.

### 4. How to fix it
Update the operand slicing loop so that:

- operand 0 and operand 1 continue to use `fp_width(src_fmt_i)`
- operand 2 uses `fp_width(dst_fmt_i)`

This can be done with a conditional inside the loop based on `i`.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>src/fpnew_opgroup_multifmt_slice.sv</file>
<original>
        for (int unsigned i = 0; i < NUM_OPERANDS; i++) begin
          local_operands[i] = operands_i[i] >> LANE*fpnew_pkg::fp_width(src_fmt_i);
        end
</original>
<patched>
        for (int unsigned i = 0; i < NUM_OPERANDS; i++) begin
          local_operands[i] = operands_i[i] >> LANE*(
              (i == 2) ? fpnew_pkg::fp_width(dst_fmt_i) : fpnew_pkg::fp_width(src_fmt_i));
        end
</patched>
```
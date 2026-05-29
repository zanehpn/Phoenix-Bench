## Phase 1: FIX ANALYSIS

### 1) What the problem is
The bug is in `fpnew_opgroup_multifmt_slice`: when slicing operands for each lane, it uses the **source FP width** (`src_fmt_i`) for **all three operands**.

That is wrong for the **third operand** in the `ADDMUL` opgroup:
- `operands_i[0]` and `operands_i[1]` use the **source format** (`src_fmt_i`)
- `operands_i[2]` and the result use the **destination format** (`dst_fmt_i`)

So for operand 2, the lane slicing must use `fp_width(dst_fmt_i)`, not `fp_width(src_fmt_i)`.

### 2) Where the problem occurs
The problem is in:

- `src/fpnew_opgroup_multifmt_slice.sv`
- inside the `always_comb begin : prepare_input` block
- specifically this loop:

```sv
for (int unsigned i = 0; i < NUM_OPERANDS; i++) begin
  local_operands[i] = operands_i[i] >> LANE*fpnew_pkg::fp_width(src_fmt_i);
end
```

This applies the same width to every operand, which is incorrect for `operands_i[2]`.

### 3) Best practices to take into account
- Keep the fix **minimal** and **localized**.
- Preserve existing behavior for:
  - operand 0
  - operand 1
  - non-`ADDMUL` opgroups
  - conversion-specific overrides already present in the code
- Avoid changing pipeline logic or unrelated formatting.
- Use the correct format width based on operand role, not a blanket width for all operands.

### 4) How to fix the problem
Update the slicing logic so that:
- operands 0 and 1 use `src_fmt_i`
- operand 2 uses `dst_fmt_i`

A straightforward fix is to compute the shift width per operand inside the loop:
- `i < 2` → `fp_width(src_fmt_i)`
- `i == 2` → `fp_width(dst_fmt_i)`

---

## Phase 2: FIX IMPLEMENTATION

```patch
<file>src/fpnew_opgroup_multifmt_slice.sv</file>
<original>
        for (int unsigned i = 0; i < NUM_OPERANDS; i++) begin
          local_operands[i] = operands_i[i] >> LANE*fpnew_pkg::fp_width(src_fmt_i);
        end
</original>
<patched>
        for (int unsigned i = 0; i < NUM_OPERANDS; i++) begin
          local_operands[i] = operands_i[i] >>
                              LANE * fpnew_pkg::fp_width((i == 2) ? dst_fmt_i : src_fmt_i);
        end
</patched>
```
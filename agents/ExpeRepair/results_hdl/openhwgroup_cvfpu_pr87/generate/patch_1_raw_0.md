## Phase 1: FIX ANALYSIS

### 1) What the problem is
The bug is in `fpnew_opgroup_multifmt_slice`: it slices **all three operands** using the width of `src_fmt_i`, but for the `ADDMUL` opgroup the **third operand** must use the width of `dst_fmt_i`.

This matters because:
- `operands_i[0]` and `operands_i[1]` are source operands and should use `src_fmt_i`
- `operands_i[2]` is the addend operand for `ADDMUL`, and its format matches `dst_fmt_i`
- Using `src_fmt_i` for operand 3 causes incorrect lane extraction for all lanes except lane 0

### 2) Where the problem occurs
The issue is in:

- `src/fpnew_opgroup_multifmt_slice.sv`

Specifically, in the lane input preparation logic:

```sv
always_comb begin : prepare_input
  for (int unsigned i = 0; i < NUM_OPERANDS; i++) begin
    local_operands[i] = operands_i[i] >> LANE*fpnew_pkg::fp_width(src_fmt_i);
  end
```

This applies the source format width to every operand, including `operands_i[2]`.

### 3) Best practices to take into account
- Make the smallest possible change.
- Preserve existing behavior for operands 0 and 1.
- Only special-case operand 2 where the opgroup/operand semantics require it.
- Avoid unnecessary refactoring or unrelated changes.
- Keep the fix local to the slicing logic.

### 4) How to fix it
Modify the operand slicing so that:
- operands 0 and 1 still use `fp_width(src_fmt_i)`
- operand 2 uses `fp_width(dst_fmt_i)` when the opgroup expects the destination-format third operand

A minimal and safe fix is to branch inside the loop:
- if `i < 2`, shift by source width
- otherwise, shift by destination width

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>src/fpnew_opgroup_multifmt_slice.sv</file>
<original>
        always_comb begin : prepare_input
          for (int unsigned i = 0; i < NUM_OPERANDS; i++) begin
            local_operands[i] = operands_i[i] >> LANE*fpnew_pkg::fp_width(src_fmt_i);
          end
          // override operand 0 for some conversions
          if (OpGroup == fpnew_pkg::CONV) begin
            // Source is an integer
            if (op_i == fpnew_pkg::I2F) begin
              local_operands[0] = operands_i[0] >> LANE*fpnew_pkg::int_width(int_fmt_i);
            // vectorial F2F up casts
            end else if (op_i == fpnew_pkg::F2F) begin
              if (vectorial_op && op_mod_i && is_up_cast) begin // up cast with upper half
                local_operands[0] = operands_i[0] >> LANE*fpnew_pkg::fp_width(src_fmt_i) +
                                                     MAX_FP_WIDTH/2;
              end
            // CPK
            end else if (dst_is_cpk) begin
              if (lane == 1) begin
                local_operands[0] = operands_i[1][LANE_WIDTH-1:0]; // using opB as second argument
              end
            end
          end
        end
</original>
<patched>
        always_comb begin : prepare_input
          for (int unsigned i = 0; i < NUM_OPERANDS; i++) begin
            local_operands[i] = operands_i[i] >> LANE*fpnew_pkg::fp_width((i < 2) ? src_fmt_i : dst_fmt_i);
          end
          // override operand 0 for some conversions
          if (OpGroup == fpnew_pkg::CONV) begin
            // Source is an integer
            if (op_i == fpnew_pkg::I2F) begin
              local_operands[0] = operands_i[0] >> LANE*fpnew_pkg::int_width(int_fmt_i);
            // vectorial F2F up casts
            end else if (op_i == fpnew_pkg::F2F) begin
              if (vectorial_op && op_mod_i && is_up_cast) begin // up cast with upper half
                local_operands[0] = operands_i[0] >> LANE*fpnew_pkg::fp_width(src_fmt_i) +
                                                     MAX_FP_WIDTH/2;
              end
            // CPK
            end else if (dst_is_cpk) begin
              if (lane == 1) begin
                local_operands[0] = operands_i[1][LANE_WIDTH-1:0]; // using opB as second argument
              end
            end
          end
        end
</patched>
```
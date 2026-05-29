## Phase 1: FIX ANALYSIS

### 1) What the problem is
The `fpnew_opgroup_multifmt_slice` slices all three operands using the bit width of `src_fmt_i`, but that is incorrect for operand 2 in the `ADDMUL` opgroup.

For `ADDMUL`:
- `operands_i[0]` and `operands_i[1]` use `src_fmt_i`
- `operands_i[2]` and the result use `dst_fmt_i`

Because the slice logic uses `src_fmt_i` for operand 2 as well, lanes after lane 0 receive the wrong bits for the third operand when `src_fmt_i != dst_fmt_i` (e.g. FP16 source, FP32 destination).

### 2) Where the problem occurs
The bug is in:

- `src/fpnew_opgroup_multifmt_slice.sv`

Specifically this block in `prepare_input`:

```systemverilog
for (int unsigned i = 0; i < NUM_OPERANDS; i++) begin
  local_operands[i] = operands_i[i] >> LANE*fpnew_pkg::fp_width(src_fmt_i);
end
```

This applies `fp_width(src_fmt_i)` to every operand, including `operands_i[2]`.

### 3) Best practices to take into account
- Make the fix as narrow as possible.
- Preserve existing behavior for operands 0 and 1.
- Only adjust operand 2 slicing when it semantically differs.
- Avoid changing unrelated pipeline or lane logic.
- Keep the code readable and consistent with the existing style.

### 4) How to fix the problem
Use a per-operand slice width:
- operands 0 and 1: `fpnew_pkg::fp_width(src_fmt_i)`
- operand 2: `fpnew_pkg::fp_width(dst_fmt_i)`

This ensures `ADDMUL` lane slicing matches the intended format contract.

---

## Phase 2: FIX IMPLEMENTATION

```systemverilog
<file>src/fpnew_opgroup_multifmt_slice.sv</file>
<original>
        // Slice out the operands for this lane, upper bits are ignored in the unit
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
        // Slice out the operands for this lane, upper bits are ignored in the unit
        always_comb begin : prepare_input
          for (int unsigned i = 0; i < NUM_OPERANDS; i++) begin
            local_operands[i] = operands_i[i] >> LANE*fpnew_pkg::fp_width(
                (i == 2) ? dst_fmt_i : src_fmt_i);
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
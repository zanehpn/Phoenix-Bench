## Phase 1: FIX ANALYSIS

### 1) What the problem is
The bug is an out-of-bounds array access in the D-side pending access tracking logic.

In the `always_comb` block, the code uses:

```systemverilog
pending_dside_accesses_shifted[i - 1].valid
```

This is unsafe when `i == 0`, because `i - 1` becomes `-1`, which is an invalid index for the array. Even though there is a special case for `i == 0` in the first branch, the `else if` still exists in the same conditional chain and can be evaluated in a way that permits the invalid reference.

### 2) Where the problem occurs
The issue occurs in `rtl/ibex_top.sv` inside the `g_dside_tracker` generate block, specifically in the `always_comb` block that builds `pending_dside_accesses_d[i]`.

The problematic section is:

```systemverilog
if (data_req_o && data_gnt_i) begin
  if (i == 0 && !pending_dside_accesses_shifted[i].valid) begin
    pending_dside_accesses_d[i].valid = 1'b1;
    pending_dside_accesses_d[i].is_read = ~data_we_o;
  end else if (pending_dside_accesses_shifted[i - 1].valid &
               !pending_dside_accesses_shifted[i].valid) begin
    pending_dside_accesses_d[i].valid = 1'b1;
    pending_dside_accesses_d[i].is_read = ~data_we_o;
  end
end
```

### 3) Best practices to take into account
- Never reference `i - 1` unless `i > 0` is explicitly guaranteed.
- Split boundary cases (`i == 0`) from general cases to make indexing logic safe and obvious.
- Keep the fix minimal and local to the unsafe access.
- Preserve existing behavior for all non-boundary indices.

### 4) How to fix the problem
Refactor the conditional so that:
- the `i == 0` case is handled separately,
- only indices `i > 0` can reach the `i - 1` access,
- the logic remains functionally equivalent.

A safe structure is:

- If `i == 0`, only check whether slot 0 is free and insert there.
- Else, check `pending_dside_accesses_shifted[i - 1].valid` and `!pending_dside_accesses_shifted[i].valid`.

This removes the possibility of out-of-bounds access.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>rtl/ibex_top.sv</file>
<original>
        if (data_req_o && data_gnt_i) begin
          if (i == 0 && !pending_dside_accesses_shifted[i].valid) begin
            pending_dside_accesses_d[i].valid = 1'b1;
            pending_dside_accesses_d[i].is_read = ~data_we_o;
          end else if (pending_dside_accesses_shifted[i - 1].valid &
               !pending_dside_accesses_shifted[i].valid) begin
            pending_dside_accesses_d[i].valid = 1'b1;
            pending_dside_accesses_d[i].is_read = ~data_we_o;
          end
        end
</original>
<patched>
        if (data_req_o && data_gnt_i) begin
          if (i == 0) begin
            if (!pending_dside_accesses_shifted[i].valid) begin
              pending_dside_accesses_d[i].valid = 1'b1;
              pending_dside_accesses_d[i].is_read = ~data_we_o;
            end
          end else if (pending_dside_accesses_shifted[i - 1].valid &
                       !pending_dside_accesses_shifted[i].valid) begin
            pending_dside_accesses_d[i].valid = 1'b1;
            pending_dside_accesses_d[i].is_read = ~data_we_o;
          end
        end
</patched>
```
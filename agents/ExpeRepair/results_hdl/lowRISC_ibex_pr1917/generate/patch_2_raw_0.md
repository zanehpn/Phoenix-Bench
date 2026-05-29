### Phase 1: FIX ANALYSIS

#### 1. What the problem is
The bug is an out-of-bounds array access in the data-side access tracking logic.  
In the `always_comb` block, the code evaluates:

```systemverilog
pending_dside_accesses_shifted[i - 1].valid
```

This is unsafe when `i == 0`, because it indexes `-1`, which is out of bounds.

#### 2. Where the problem occurs
The issue is in `rtl/ibex_top.sv` inside the `g_dside_tracker` generate loop, specifically in this conditional branch:

```systemverilog
else if (pending_dside_accesses_shifted[i - 1].valid &
         !pending_dside_accesses_shifted[i].valid) begin
```

Even though there is a special case for `i == 0` earlier in the block, the code still relies on the later branch being unreachable for `i == 0`. The logic should be structured so that the `i == 0` case is explicitly separated and cannot accidentally evaluate `i - 1`.

#### 3. Best practices to take into account
- Avoid array indexing expressions that can underflow, even if guarded indirectly.
- Explicitly separate boundary cases (`i == 0`, last index, etc.) from general cases.
- Prefer clarity over compact conditional logic in hardware generate/always blocks.
- Preserve existing behavior while making the logic structurally safe.

#### 4. How to fix the problem
Refactor the `always_comb` block so that:
- the `i == 0` case is handled separately,
- the `i > 0` case is only evaluated when safe,
- the logic never references `i - 1` unless `i > 0`.

A minimal fix is to restructure the request-grant handling into an explicit `if (i == 0) ... else ...` form, and only use `i - 1` in the `else` branch.

---

### Phase 2: FIX IMPLEMENTATION

```text
<file>rtl/ibex_top.sv</file>
<original>
      always_comb begin
        pending_dside_accesses_d[i] = pending_dside_accesses_shifted[i];

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
      end
</original>
<patched>
      always_comb begin
        pending_dside_accesses_d[i] = pending_dside_accesses_shifted[i];

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
      end
</patched>
```


## Phase 1: FIX ANALYSIS

### 1. Problem statement
The issue is an out-of-bounds array access in the data-side access tracking logic in `ibex_top.sv`.

In the `always_comb` block that updates `pending_dside_accesses_d[i]`, the code evaluates:

```systemverilog
pending_dside_accesses_shifted[i - 1].valid
```

when `i == 0` is possible. That means the design can attempt to read index `-1`, which is invalid and can cause simulation/synthesis issues or undefined behavior.

### 2. Where the problem occurs
The problematic code is in:

- `rtl/ibex_top.sv`
- inside the `for (genvar i = 0; i < MaxOutstandingDSideAccesses; i++) begin : g_dside_tracker`
- specifically in the `always_comb` block around the request-grant logic:

```systemverilog
if (data_req_o && data_gnt_i) begin
  if (i == 0 && !pending_dside_accesses_shifted[i].valid) begin
    ...
  end else if (pending_dside_accesses_shifted[i - 1].valid &
               !pending_dside_accesses_shifted[i].valid) begin
    ...
  end
end
```

Even though the `i == 0` case is handled first, the structure relies on conditional evaluation behavior in a way that is fragile and still flagged as an out-of-bounds risk. The fix should explicitly separate the `i == 0` case from all other cases.

### 3. Best practices to follow
- Avoid any expression that can index arrays with negative values, even if guarded by a condition.
- Explicitly separate boundary cases (`i == 0`) from general cases (`i > 0`).
- Keep the change minimal and localized to the affected logic.
- Preserve the existing behavior for all valid indices.
- Prefer clear, structurally safe control flow over relying on short-circuiting or nested conditions.

### 4. How to fix it
Refactor the `always_comb` block so that:

- when `i == 0`, only the `i == 0` logic is evaluated;
- for `i > 0`, the logic using `i - 1` is evaluated only in that branch.

A clean way is to wrap the request-grant update logic in:

```systemverilog
if (i == 0) begin
  ...
end else begin
  ...
end
```

This guarantees `i - 1` is never evaluated when `i == 0`.

---

## Phase 2: FIX IMPLEMENTATION

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
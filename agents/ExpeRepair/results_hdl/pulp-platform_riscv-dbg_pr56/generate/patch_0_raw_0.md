## Phase 1: FIX ANALYSIS

### 1) What the problem is
The issue is an off-by-one error in the loop bound inside `src/dm_csrs.sv`.  
The loop iterates over `halted_reshaped0`, but its upper bound is computed as:

```sv
NrHarts/2**5+1
```

This can exceed the actual declared size of `halted_reshaped0`, which is:

```sv
logic [(NrHarts-1)/2**5:0][31:0] halted_reshaped0;
```

So the loop may access a non-existing element at the end of the array.

### 2) Where the problem occurs
The bug is in `src/dm_csrs.sv`, in the `always_comb` block for `p_reduction1`:

```sv
for (int unsigned k = 0; k < NrHarts/2**5+1; k++) begin
  halted_flat1[k] = |halted_reshaped0[k];
end
```

This loop should match the declared size of `halted_reshaped0`.

### 3) Best practices to take into account
- Use array bounds that exactly match the declared array dimensions.
- Prefer formulas based on the same expression used in the array declaration to avoid divergence.
- Avoid bounds that depend on a different rounding behavior than the array indexing range.
- Keep the fix minimal and localized to the incorrect loop.

### 4) How to fix the problem
Change the loop bound from:

```sv
NrHarts/2**5+1
```

to:

```sv
(NrHarts-1)/2**5+1
```

This makes the loop iterate exactly over the valid indices of `halted_reshaped0`.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>src/dm_csrs.sv</file>
<original>
    for (int unsigned k = 0; k < NrHarts/2**5+1; k++) begin
      halted_flat1[k] = |halted_reshaped0[k];
    end
</original>
<patched>
    for (int unsigned k = 0; k < (NrHarts-1)/2**5+1; k++) begin
      halted_flat1[k] = |halted_reshaped0[k];
    end
</patched>
```
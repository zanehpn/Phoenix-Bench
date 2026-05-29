## Phase 1: FIX ANALYSIS

### 1. What the problem is
The comparison logic in `fpnew_noncomp.sv` treats NaNs specially for the `not equal` comparison, but only when the NaN is **quiet**.  
For **signaling NaNs**, the logic incorrectly clears the result bit instead of setting it for `not equal`.

This makes quiet and signaling NaNs behave inconsistently in `NE` comparisons, and it does not match the intended RISC-V comparison behavior described in the issue.

### 2. Where the problem occurs
The bug is in:

- `src/fpnew_noncomp.sv`
- the comparison block under `// Comparisons`
- specifically the `fpnew_pkg::RDN` case:

```sv
fpnew_pkg::RDN: begin // Equal
  if (any_operand_nan) cmp_result = inp_pipe_op_mod_q[NUM_INP_REGS]; // NaN always not equal
  else cmp_result = operands_equal ^ inp_pipe_op_mod_q[NUM_INP_REGS];
end
```

Also relevant is the earlier reduction:

```sv
assign signalling_nan  = (| {info_a.is_signalling, info_b.is_signalling});
```

The current code already detects signaling NaNs, but that signal is only used to force `NV` for some cases, not to produce the correct `not equal` result when the compare is modified.

### 3. Best practices to take into account
- Make the smallest possible change to preserve existing behavior.
- Keep the compare semantics aligned with the intended RISC-V behavior.
- Ensure both quiet and signaling NaNs are handled consistently in `not equal`.
- Avoid changing unrelated comparison modes or status-flag behavior unless necessary.
- Preserve the existing modifier-bit behavior (`op_mod_q`) since the comment indicates it inverts the compare result.

### 4. How to fix the problem
Update the `RDN` comparison case so that `not equal` returns true when **either operand is any NaN**, including signaling NaNs.

A minimal fix is to change the NaN check in the `RDN` branch from `any_operand_nan` to `any_operand_nan || signalling_nan`, or equivalently to use `any_operand_nan` if that signal is already guaranteed to include signaling NaNs.  
However, based on the reported bug and the provided code, the safest explicit fix is to include signaling NaNs in the condition used to set the result bit for `not equal`.

---

## Phase 2: FIX IMPLEMENTATION

```diff
<file>src/fpnew_noncomp.sv</file>
<original>
        fpnew_pkg::RDN: begin // Equal
          if (any_operand_nan) cmp_result = inp_pipe_op_mod_q[NUM_INP_REGS]; // NaN always not equal
          else cmp_result = operands_equal ^ inp_pipe_op_mod_q[NUM_INP_REGS];
        end
</original>
<patched>
        fpnew_pkg::RDN: begin // Equal
          if (any_operand_nan || signalling_nan) cmp_result = inp_pipe_op_mod_q[NUM_INP_REGS]; // NaN always not equal
          else cmp_result = operands_equal ^ inp_pipe_op_mod_q[NUM_INP_REGS];
        end
</patched>
```


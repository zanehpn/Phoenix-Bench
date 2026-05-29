Phase 1: FIX ANALYSIS

1. Problem summary
- The NONCOMP compare logic treats quiet NaNs correctly for “not equal” comparisons, but signaling NaNs are handled differently.
- In the `RDN` compare path, when either operand is a NaN, the result bit is set only for quiet NaNs via `any_operand_nan`.
- If a signaling NaN is present, the code instead takes the earlier `signalling_nan` branch and only raises `NV`, leaving the result bit cleared.
- This makes quiet and signaling NaNs inconsistent for the not-equal case, and diverges from the intended RISC-V compare behavior where `!=` should evaluate true for NaNs while also raising invalid for signaling NaNs.

2. Where the problem occurs
- The issue is in `src/fpnew_noncomp.sv`, inside the comparison logic around the `always_comb begin : comparisons` block.
- Specifically, the `fpnew_pkg::RDN` branch:
  - `if (any_operand_nan) cmp_result = inp_pipe_op_mod_q[NUM_INP_REGS];`
  - This uses `any_operand_nan`, which does not include signaling NaNs if the earlier `signalling_nan` check prevents reaching this code.
- The relevant earlier logic is:
  - `if (signalling_nan) cmp_status.NV = 1'b1;`
  - `else begin ...`
- Because that `else` blocks the `RDN` NaN result assignment for signaling NaNs, the result bit is not set for `!=` with signaling NaNs.

3. Best practices to take into account
- Keep the fix minimal and localized to the comparison block.
- Preserve existing invalid-operation flag behavior for signaling NaNs.
- Ensure quiet and signaling NaNs are handled consistently in the `not equal` path.
- Avoid changing unrelated comparison semantics for `<`, `<=`, or `==`.
- Match the intended RISC-V comparison convention: NaNs should make `!=` true, while signaling NaNs also raise `NV`.

4. How to fix it
- Adjust the `RDN` compare branch so that signaling NaNs also set the result bit for `not equal`.
- The simplest safe approach is to make the NaN check in the `RDN` branch consider both quiet and signaling NaNs, while keeping the existing `NV` flag setting.
- A minimal change is to use `any_operand_nan || signalling_nan` in the `RDN` branch, or equivalently ensure the result assignment occurs for signaling NaNs as well.
- Since `signalling_nan` is already separately handled to set `NV`, the final result for `!=` should still be true when any NaN is present.

Phase 2: FIX IMPLEMENTATION

```text
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
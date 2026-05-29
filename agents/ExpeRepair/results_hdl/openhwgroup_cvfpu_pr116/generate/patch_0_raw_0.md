## Phase 1: FIX ANALYSIS

### 1) What the problem is
The comparison logic in `fpnew_noncomp.sv` treats NaN operands specially for the **equal / not-equal** compare path, but it only checks `any_operand_nan` without distinguishing quiet NaNs from signaling NaNs.

The issue report says the intended behavior is:

- For comparisons, NaNs should generally make the result false and raise invalid when appropriate.
- For **not-equal** comparisons, encountering any NaN should set the result bit.
- Quiet and signaling NaNs should be handled consistently.
- The current implementation fails to set the result bit for **signaling NaNs** in the not-equal compare path.

### 2) Where the problem occurs
The bug is in:

- `src/fpnew_noncomp.sv`
- the **Comparisons** `always_comb` block
- specifically the `fpnew_pkg::RDN` case:

```systemverilog
fpnew_pkg::RDN: begin // Equal
  if (any_operand_nan) cmp_result = inp_pipe_op_mod_q[NUM_INP_REGS]; // NaN always not equal
  else cmp_result = operands_equal ^ inp_pipe_op_mod_q[NUM_INP_REGS];
end
```

The block already computes:

```systemverilog
logic signalling_nan;
assign signalling_nan = (| {info_a.is_signalling, info_b.is_signalling});
```

But that signal is only used at the top-level invalid check:

```systemverilog
if (signalling_nan) cmp_status.NV = 1'b1;
```

It is not used to ensure the not-equal result bit is set when a signaling NaN is present.

### 3) Best practices to take into account
- **Minimize the change**: only adjust the compare behavior, not unrelated logic.
- **Preserve existing behavior** for non-NaN comparisons and for other compare modes.
- **Keep RISC-V alignment**: comparisons with NaNs should match the intended spec behavior and the implementation’s documented semantics.
- **Use existing signals**: reuse `signalling_nan` rather than introducing duplicate checks.

### 4) How to fix the problem
Update the `RDN` compare case so that the result bit is set for **any NaN**, including signaling NaNs, when the operation is the not-equal variant.

A precise fix is:

- Keep invalid flag behavior unchanged.
- In the `RDN` case, make the NaN branch explicitly cover the signaling-NaN situation too.
- Since `signalling_nan` is already computed, use it to ensure the not-equal result is asserted consistently.

---

## Phase 2: FIX IMPLEMENTATION

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


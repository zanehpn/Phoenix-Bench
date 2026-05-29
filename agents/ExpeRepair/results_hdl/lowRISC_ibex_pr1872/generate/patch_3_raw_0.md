## Phase 1: FIX ANALYSIS

### 1. What the problem is
The coverpoint `insn_trigger_exception` is intended to count when an instruction-trigger match causes an exception/flush path. The issue report says that `riscv_debug_triggers_test` generates the right stimulus and the instruction retires, but this coverpoint never triggers.

In other words: the design behavior occurs, but the coverage expression is sampling the wrong signal combination or at the wrong time, so the coverage event is missed.

### 2. Where the problem occurs
The relevant code is in:

- `dv/uvm/core_ibex/fcov/core_ibex_fcov_if.sv`

Specifically, this coverpoint:

```systemverilog
`DV_FCOV_EXPR_SEEN(insn_trigger_exception, instr_id_matches_trigger_q &&
                                           id_stage_i.controller_i.fcov_pipe_flush)
```

and the related staging logic:

```systemverilog
assign instr_id_matches_trigger_d = id_stage_i.controller_i.trigger_match_i &&
                                    id_stage_i.controller_i.fcov_debug_entry_if;
```

### 3. Best practices to take into account
- Keep the fix minimal: only adjust the coverage condition, not unrelated logic.
- Preserve the intended meaning of the coverage point: it should fire when a trigger match causes an exception/flush, not when unrelated debug entry conditions happen.
- Prefer using the already-available trigger-match history signal if it represents the event being covered.
- Avoid introducing new state unless strictly necessary.

### 4. How to fix the problem
The current trigger-match history signal is gated by `fcov_debug_entry_if`, which is appropriate for the debug-entry coverage point, but not for the exception case. That means `instr_id_matches_trigger_q` may never be asserted for the exception-triggering stimulus, so `insn_trigger_exception` cannot hit.

The fix is to make the delayed trigger-match signal reflect trigger matches independently of debug-entry conditions, and then keep the coverpoint using the flush condition as the exception discriminator.

Concretely:
- Change `instr_id_matches_trigger_d` to depend only on `trigger_match_i`
- Keep `insn_trigger_exception` as `instr_id_matches_trigger_q && fcov_pipe_flush`

This preserves the debug-entry coverpoint semantics while allowing the exception coverpoint to observe trigger matches that do not also qualify as debug entry.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>dv/uvm/core_ibex/fcov/core_ibex_fcov_if.sv</file>
<original>
assign instr_id_matches_trigger_d = id_stage_i.controller_i.trigger_match_i &&
                                    id_stage_i.controller_i.fcov_debug_entry_if;

// Delay instruction matching trigger point since it is catched in IF stage.
// We would want to cross it with decoded instruction categories and it does not matter
// when exactly we are hitting the condition.
always @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    instr_id_matches_trigger_q <= 1'b0;
  end else begin
    instr_id_matches_trigger_q <= instr_id_matches_trigger_d;
  end
end
</original>
<patched>
assign instr_id_matches_trigger_d = id_stage_i.controller_i.trigger_match_i;

// Delay instruction matching trigger point since it is catched in IF stage.
// We would want to cross it with decoded instruction categories and it does not matter
// when exactly we are hitting the condition.
always @(posedge clk_i or negedge rst_ni) begin
  if (!rst_ni) begin
    instr_id_matches_trigger_q <= 1'b0;
  end else begin
    instr_id_matches_trigger_q <= instr_id_matches_trigger_d;
  end
end
</patched>
```


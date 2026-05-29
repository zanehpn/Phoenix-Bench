### Phase 1: FIX ANALYSIS

#### 1) What the problem is
The module instantiation of `adbg_lintonly_top` in `lint_jtag_wrap.sv` leaves one input port unconnected:

- `lint_r_aux_i`

This is a lint/debug interface signal, and leaving it open can produce warnings/errors during compilation or linting, and may violate module interface expectations.

#### 2) Where the problem occurs
The issue occurs in:

- `rtl/pulp_soc/lint_jtag_wrap.sv`

Specifically in the instantiation of `dbg_module_i` (`adbg_lintonly_top`) where:

```systemverilog
.lint_r_aux_i   (                          ),
```

is left unconnected.

#### 3) Best practices to take into account
- **Connect all declared input ports** of instantiated modules, even if the signal is unused.
- If a signal is not functionally needed, connect it to a **constant of the correct width/type** rather than leaving it open.
- Prefer **explicit, self-documenting ties** for unused interface fields to avoid lint issues and improve code clarity.
- Keep the fix **minimal** and avoid unrelated refactoring.

#### 4) How to fix the problem
Connect `lint_r_aux_i` to a constant value of the appropriate width instead of leaving it unconnected.  
Since this is an auxiliary response field and appears unused in this wrapper, the safest minimal fix is to tie it to `'0`.

---

### Phase 2: FIX IMPLEMENTATION

```text
<file>rtl/pulp_soc/lint_jtag_wrap.sv</file>
<original>
        .lint_gnt_i     ( jtag_lint_master.gnt     ),
        .lint_r_aux_i   (                          ),
        .lint_r_valid_i ( jtag_lint_master.r_valid ),
</original>
<patched>
        .lint_gnt_i     ( jtag_lint_master.gnt     ),
        .lint_r_aux_i   ( '0                       ),
        .lint_r_valid_i ( jtag_lint_master.r_valid ),
</patched>
```
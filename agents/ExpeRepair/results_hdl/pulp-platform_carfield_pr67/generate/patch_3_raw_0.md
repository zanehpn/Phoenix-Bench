## Phase 1: FIX ANALYSIS

### 1) What the problem is
The Safety Island boot mode is currently hardcoded inside `hw/carfield.sv`:

```systemverilog
safety_island_pkg::bootmode_e safety_island_bootmode;
assign safety_island_bootmode = safety_island_pkg::Preloaded;
```

The issue request says to “Propagate bootmode for safety Island” and points to the top-level module, which means the Safety Island should not always use `Preloaded`; instead, it should receive boot mode from the top-level `carfield` interface, like the other boot-mode inputs already do.

### 2) Where the problem occurs
The problematic logic is in `hw/carfield.sv` around the Safety Island setup:

- A local signal `safety_island_bootmode` is declared
- It is assigned a fixed constant `safety_island_pkg::Preloaded`
- That signal is then connected to `i_safety_island_wrap.bootmode_i`

This makes the Safety Island boot mode non-configurable from the top level.

### 3) Best practices to take into account
- Prefer top-level propagation of configuration inputs instead of hardcoding behavior in the SoC top module.
- Keep the change minimal: only replace the constant with a proper input path.
- Preserve existing type compatibility with `safety_island_pkg::bootmode_e`.
- Avoid changing unrelated subsystems; only touch the Safety Island bootmode wiring if that is the issue.

### 4) How to fix the problem
Add a top-level input for the Safety Island boot mode in `carfield` and connect it to the Safety Island wrapper instead of assigning a constant.

Concretely:
- Introduce an input port such as `bootmode_safety_island_i` in `module carfield`
- Replace the constant assignment with a direct assignment from that input
- Keep the wrapper connection unchanged except for sourcing the new signal

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>hw/carfield.sv</file>
<original>
  // Safety Island BOOT pins
  input   logic [1:0]                                 bootmode_safe_isln_i,
  // Host UART Interface
</original>
<patched>
  // Safety Island BOOT pins
  input   logic [1:0]                                 bootmode_safe_isln_i,
  // Safety Island boot mode
  input   safety_island_pkg::bootmode_e               safety_island_bootmode_i,
  // Host UART Interface
</patched>
```

```text
<file>hw/carfield.sv</file>
<original>
 // TODO: propagate to top
 safety_island_pkg::bootmode_e safety_island_bootmode;
 assign safety_island_bootmode = safety_island_pkg::Preloaded;
</original>
<patched>
 safety_island_pkg::bootmode_e safety_island_bootmode;
 assign safety_island_bootmode = safety_island_bootmode_i;
</patched>
```
## Phase 1: FIX ANALYSIS

### 1. Problem summary
The issue is that the Safety Island boot mode is currently hardcoded inside `hw/carfield.sv`:

- `safety_island_bootmode` is assigned to `safety_island_pkg::Preloaded`
- there is a TODO comment saying it should be propagated to the top

This means the top-level `carfield` module does not expose a boot mode input for the Safety Island, so its boot mode cannot be controlled externally.

### 2. Where the problem occurs
The relevant code is in `hw/carfield.sv`, in the Safety Island section:

- a local signal is declared:
  - `safety_island_pkg::bootmode_e safety_island_bootmode;`
- it is then hardcoded:
  - `assign safety_island_bootmode = safety_island_pkg::Preloaded;`
- later it is passed into `i_safety_island_wrap` via:
  - `.bootmode_i (safety_island_bootmode)`

The top-level module already has boot-related inputs for the main system and secure subsystem, so Safety Island should follow the same pattern.

### 3. Best practices to consider
- Keep the change minimal and localized.
- Expose configuration control at the top level rather than hardcoding subsystem behavior.
- Preserve existing behavior by setting a sensible default if needed.
- Ensure the new top-level signal uses the correct type (`safety_island_pkg::bootmode_e` or a compatible encoded input).
- Avoid changing unrelated module wiring.

### 4. How to fix it
Add a Safety Island bootmode input to the `carfield` top-level module ports and connect it directly to `i_safety_island_wrap.bootmode_i`.

Since the current code already uses a typed internal signal, the cleanest fix is:

- add a top-level input port for Safety Island boot mode
- remove the local hardcoded assignment
- connect the new input directly to the wrapper

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>hw/carfield.sv</file>
<original>
  // Safety Island
  logic [SafetyIslandCfg.NumInterrupts-1:0] safed_intrs;

  // TODO: propagate to top
  safety_island_pkg::bootmode_e safety_island_bootmode;
  assign safety_island_bootmode = safety_island_pkg::Preloaded;

  assign safed_intrs  = {
    59'h0,
    spatzcl_safed_mbox_intr, // from spatzcl
    pulpcl_safed_mbox_intr,  // from pulpcl
    secd_safed_mbox_intr,    // from secd
    hostd_safed_mbox_intr    // from hostd
  };
</original>
<patched>
  // Safety Island
  logic [SafetyIslandCfg.NumInterrupts-1:0] safed_intrs;

  assign safed_intrs  = {
    59'h0,
    spatzcl_safed_mbox_intr, // from spatzcl
    pulpcl_safed_mbox_intr,  // from pulpcl
    secd_safed_mbox_intr,    // from secd
    hostd_safed_mbox_intr    // from hostd
  };
</patched>
```

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
   .rst_ni                 ( safety_rst_n                             ),
   .pwr_on_rst_ni          ( safety_pwr_on_rst_n                      ),
   .test_enable_i          ( '0                                       ),
   .bootmode_i             ( safety_island_bootmode                   ),
   .fetch_en_i             ( car_regs_reg2hw.safety_island_fetch_enable ), // To SoC Bus
</original>
<patched>
   .rst_ni                 ( safety_rst_n                             ),
   .pwr_on_rst_ni          ( safety_pwr_on_rst_n                      ),
   .test_enable_i          ( '0                                       ),
   .bootmode_i             ( safety_island_bootmode_i                  ),
   .fetch_en_i             ( car_regs_reg2hw.safety_island_fetch_enable ), // To SoC Bus
</patched>
```


## Phase 1: FIX ANALYSIS

### 1. What the problem is
The Safety Island boot mode is currently hardcoded locally inside `hw/carfield.sv`:

```systemverilog
safety_island_pkg::bootmode_e safety_island_bootmode;
assign safety_island_bootmode = safety_island_pkg::Preloaded;
```

The issue comment says: **“Propagate bootmode for safety Island”** and points to the top-level file.  
This indicates the Safety Island boot mode should not be fixed to `Preloaded` inside the top module; instead, it should be provided from the top level so it can be configured externally, similar to other boot-related controls.

### 2. Where the problem occurs
The relevant code is in `hw/carfield.sv` around the Safety Island instantiation:

- The local declaration and constant assignment:
  - `safety_island_bootmode`
  - `assign safety_island_bootmode = safety_island_pkg::Preloaded;`
- The connection into `i_safety_island_wrap`:
  - `.bootmode_i ( safety_island_bootmode )`

This means the wrapper is already wired to accept a boot mode, but the top module does not expose it as an input and instead forces a fixed value.

### 3. Best practices to take into account
- **Keep the fix minimal**: only change the top-level interface and wiring needed to propagate the boot mode.
- **Avoid hardcoding platform policy inside the module**: boot configuration should come from the system top-level or integration layer.
- **Preserve compatibility with existing connections**: if there is already a suitable top-level bootmode input for the Safety Island, reuse it rather than introducing duplicate signals.
- **Keep typing explicit**: use `safety_island_pkg::bootmode_e` consistently.

### 4. How to fix the problem
The cleanest fix is to **propagate the Safety Island boot mode from the top-level port into `carfield`** and connect that signal to `i_safety_island_wrap.bootmode_i`.

That means:
1. Add a new top-level input port for the Safety Island boot mode in `carfield.sv`.
2. Remove the local constant assignment.
3. Connect the new input directly to `.bootmode_i`.

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
</original>
<patched>
  // Safety Island
  logic [SafetyIslandCfg.NumInterrupts-1:0] safed_intrs;
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
   .bootmode_i             ( bootmode_safe_isln_i                     ),
   .fetch_en_i             ( car_regs_reg2hw.safety_island_fetch_enable ), // To SoC Bus
</patched>
```

```text
<file>hw/carfield.sv</file>
<original>
   // Secure Subsystem BOOT pins
   input   logic [1:0]                                 bootmode_ot_i,
   // unused by safety island -- tdo pad always out mode
   output  logic                                       jtag_safe_isln_tdo_oe_o,
   // Safety Island BOOT pins
   input   logic [1:0]                                 bootmode_safe_isln_i,
</original>
<patched>
   // Secure Subsystem BOOT pins
   input   logic [1:0]                                 bootmode_ot_i,
   // unused by safety island -- tdo pad always out mode
   output  logic                                       jtag_safe_isln_tdo_oe_o,
   // Safety Island BOOT pins
   input   logic [SafetyIslandBootmodeWidth-1:0]       bootmode_safe_isln_i,
</patched>
```

### Notes
- This patch assumes the Safety Island bootmode signal should be propagated from the top-level input `bootmode_safe_isln_i`.
- If the package defines a specific width/type alias for the bootmode instead of a raw vector width, that alias should be preferred.
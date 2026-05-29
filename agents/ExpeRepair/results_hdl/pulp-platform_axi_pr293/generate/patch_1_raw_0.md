## Phase 1: FIX ANALYSIS

### 1) What the problem is
`axi_pkg::burst_t` was changed from a plain fixed-width typedef to a width that depends on the Verilog parameter `BurstWidth` via `$size(burst_t)`.  
This breaks Vivado IP packaging because Vivado requires top-level IP port types to be directly describable in the HDL file’s port declaration, and it does not handle package typedefs that depend on package parameters in this context.

In short: using `axi_pkg::burst_t` as part of a top-level packaged IP interface is no longer Vivado-compatible.

### 2) Where the problem occurs
The issue is rooted in `src/axi_pkg.sv`:

- `burst_t` is defined as a typedef.
- `BurstWidth` is then derived from `$size(burst_t)`.
- `aw_width()` and `ar_width()` use `BurstWidth` in width calculations.

Relevant locations from the provided code:
- **Location #1**:  
  ```systemverilog
  typedef logic [1:0]  burst_t;
  parameter int unsigned BurstWidth  = $size(burst_t);
  ```
- **Locations #2 and #4**:  
  `BurstWidth` is used in `aw_width()` and `ar_width()`.

### 3) Best practices to take into account
- Keep package-level constants self-contained and tool-friendly.
- Avoid making top-level interface typing depend on package-internal `$size()` expressions when targeting Vivado IP packaging.
- Prefer explicit numeric parameters for widths when they are part of interface definitions.
- Preserve backward compatibility and minimize code changes.
- Ensure width constants remain consistent with their associated typedefs.

### 4) How to fix the problem
The best fix is to define the width first as a plain numeric parameter, then define the typedef from that parameter.

That means changing:
- `burst_t` should be declared using `BurstWidth`
- `BurstWidth` should be a fixed numeric constant, not derived from `$size(burst_t)`

This removes the dependency cycle and makes the package more Vivado-friendly.

Concretely:
- Replace `typedef logic [1:0] burst_t;`
- with a width parameter and `typedef logic [BurstWidth-1:0] burst_t;`
- Set `BurstWidth = 2`

This is minimal and matches the suggested direction mentioned in the issue.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>src/axi_pkg.sv</file>
<original>
  /// AXI Transaction Burst Width.
  typedef logic [1:0]  burst_t;
  /// AXI Transaction Response Type.
  typedef logic [1:0]   resp_t;
  /// AXI Transaction Cacheability Type.
  typedef logic [3:0]  cache_t;
  /// AXI Transaction Protection Type.
  typedef logic [2:0]   prot_t;
  /// AXI Transaction Quality of Service Type.
  typedef logic [3:0]    qos_t;
  /// AXI Transaction Region Type.
  typedef logic [3:0] region_t;
  /// AXI Transaction Length Type.
  typedef logic [7:0]    len_t;
  /// AXI Transaction Size Type.
  typedef logic [2:0]   size_t;
  /// AXI5 Atomic Operation Type.
  typedef logic [5:0]   atop_t; // atomic operations
  /// AXI5 Non-Secure Address Identifier.
  typedef logic [3:0]  nsaid_t;

  /// AXI Transaction Burst Width.
  parameter int unsigned BurstWidth  = $size(burst_t);
</original>
<patched>
  /// AXI Transaction Burst Width.
  parameter int unsigned BurstWidth  = 2;
  typedef logic [BurstWidth-1:0] burst_t;
  /// AXI Transaction Response Type.
  typedef logic [1:0]   resp_t;
  /// AXI Transaction Cacheability Type.
  typedef logic [3:0]  cache_t;
  /// AXI Transaction Protection Type.
  typedef logic [2:0]   prot_t;
  /// AXI Transaction Quality of Service Type.
  typedef logic [3:0]    qos_t;
  /// AXI Transaction Region Type.
  typedef logic [3:0] region_t;
  /// AXI Transaction Length Type.
  typedef logic [7:0]    len_t;
  /// AXI Transaction Size Type.
  typedef logic [2:0]   size_t;
  /// AXI5 Atomic Operation Type.
  typedef logic [5:0]   atop_t; // atomic operations
  /// AXI5 Non-Secure Address Identifier.
  typedef logic [3:0]  nsaid_t;
</patched>
```


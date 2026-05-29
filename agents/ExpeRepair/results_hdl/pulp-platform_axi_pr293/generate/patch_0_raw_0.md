## Phase 1: FIX ANALYSIS

### 1) What the problem is
`axi_pkg::burst_t` was changed from a fixed-width typedef (`logic [1:0]`) to a width that depends on `BurstWidth`, which is derived from a package parameter using `$size(...)`.

Vivado IP packager requires top-level HDL ports to be directly describable from the HDL file, and it does not handle this kind of package-dependent typedef in IP port declarations well. As a result, custom Vivado IPs using `axi_pkg::burst_t` at their top level fail packaging.

### 2) Where the problem occurs
The relevant problematic location is:

- `src/axi_pkg.sv`
  - `burst_t` typedef at the top of the package
  - `BurstWidth` parameter derived from `$size(burst_t)`
  - any code using `BurstWidth` in width computations is indirectly tied to the same issue

From the provided locations, the core issue is specifically:

- `typedef logic [1:0] burst_t;`
- `parameter int unsigned BurstWidth = $size(burst_t);`

The downstream width functions (`aw_width`, `ar_width`) use `BurstWidth`, but they are not the root cause. The root cause is the typedef/parameter coupling that makes the type less friendly to Vivado packaging.

### 3) Best practices to take into account
- Keep top-level HDL port types simple and statically obvious to IP packagers.
- Avoid deriving package-visible type widths from `$size(...)` of typedefs when those typedefs are used in module port declarations.
- Prefer a pattern where:
  - the numeric width is defined first as a plain constant/parameter,
  - the typedef is derived from that numeric width.
- Make minimal changes to preserve existing behavior and avoid rippling interface changes through the codebase.

### 4) How to fix the problem
The best fix is to invert the dependency:

- define `BurstWidth` as a numeric constant directly, e.g. `2`
- define `burst_t` using `BurstWidth`, e.g. `typedef logic [BurstWidth-1:0] burst_t;`

This keeps the externally used type stable and makes the width explicit, which is more compatible with Vivado IP packaging.

No other changes are necessary in the shown code unless there are separate usages that still depend on the old direction of the dependency.

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
  parameter int unsigned BurstWidth  = 32'd2;
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

  /// AXI Transaction Burst Type.
  typedef logic [BurstWidth-1:0] burst_t;
</patched>
```
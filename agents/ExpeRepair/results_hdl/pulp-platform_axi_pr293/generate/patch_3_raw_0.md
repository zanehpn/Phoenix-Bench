## Phase 1: FIX ANALYSIS

### 1. What the problem is
`axi_pkg::burst_t` was changed from a plain typedef with a fixed bit-width to a typedef whose width is tied to a package parameter (`BurstWidth = $size(burst_t)`).

Vivado IP packager does not like package-based type/parameter dependencies for top-level IP ports unless the HDL file explicitly contains the port descriptions in a form Vivado can resolve. As a result, custom Vivado IPs that expose `axi_pkg::burst_t`-based structures at their top level can no longer be packaged correctly.

The issue is not with the functional AXI logic itself, but with how type widths are defined and derived for Vivado compatibility.

### 2. Where the problem occurs
The relevant code is in `src/axi_pkg.sv`, specifically:

- `burst_t` definition
- `BurstWidth` parameter definition

The root cause is this dependency chain:

- `burst_t` is defined as a typedef
- `BurstWidth` is derived from `$size(burst_t)`
- then other functions use `BurstWidth` in width computations

The problematic lines are in Location #1, and the downstream consumers are the width functions in Locations #2, #4, #5.

### 3. Best practices to take into account
- Keep package constants and typedef widths independent of parameter evaluation when possible.
- Prefer explicit numeric width parameters for tool compatibility, especially with vendor IP packagers.
- Preserve backward compatibility for the rest of the AXI package API.
- Make the smallest possible change to fix Vivado packaging without changing the semantics of the AXI types.

### 4. How to fix the problem
The best fix is to define the typedef width numerically first, and then define the type using that parameter, rather than deriving the parameter from `$size(typedef)`.

In practice:
- change `burst_t` to use a numeric width directly (`logic [BurstWidth-1:0]`)
- set `BurstWidth` to the literal value `32'd2`
- optionally use the same style for other widths if needed, but the reported issue is specifically about `burst_t` / `BurstWidth`

This removes the circular/tool-unfriendly dependency and makes Vivado IP packager able to resolve the port types.

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
  /// AXI Transaction Response Width.
  parameter int unsigned RespWidth   = $size(resp_t);
</original>
<patched>
  /// AXI Transaction Burst Width.
  parameter int unsigned BurstWidth  = 32'd2;
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

  /// AXI Transaction Response Width.
  parameter int unsigned RespWidth   = $size(resp_t);
</patched>
```


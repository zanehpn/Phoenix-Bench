### Phase 1: FIX ANALYSIS

#### 1) What the problem is
`axi_pkg::burst_t` is currently used to derive `BurstWidth` via:

```systemverilog
parameter int unsigned BurstWidth = $size(burst_t);
```

Vivado IP packager does not like top-level IP port types that depend on package-local typedefs/parameters in a way that is not directly visible in the HDL port description. Because of that, using `axi_pkg::burst_t` in a custom packaged Vivado IP top can fail packaging, even though the code is otherwise valid SystemVerilog.

The issue is not with AXI semantics; it is a Vivado compatibility problem caused by how the width is derived.

#### 2) Where the problem occurs
The problematic code is in `src/axi_pkg.sv`, specifically:

- `burst_t` typedef declaration
- `BurstWidth` parameter definition
- downstream uses of `BurstWidth` in `aw_width()` and `ar_width()`

Relevant locations from the provided snippets:
- **Location #1**: `typedef logic [1:0] burst_t;` and `parameter int unsigned BurstWidth = $size(burst_t);`
- **Location #2**: `aw_width()` uses `BurstWidth`
- **Location #4 / #5**: `ar_width()` uses `BurstWidth`

#### 3) Best practices to take into account
- Keep the fix **minimal** and avoid changing unrelated API behavior.
- Preserve the intended bit width of AXI burst fields (`2 bits`) without relying on a package typedef for size inference.
- Prefer **explicit numeric constants** for widths when tool compatibility is an issue, especially for vendor IP packagers.
- Ensure existing functions still compute the same widths so downstream code remains unaffected.
- Avoid introducing broader refactors unless necessary.

#### 4) How to fix the problem
Make `BurstWidth` independent of the `burst_t` typedef by assigning it an explicit numeric value, e.g. `32'd2`, instead of `$size(burst_t)`.

This preserves the same functionality while avoiding the Vivado packaging issue. No other logic changes are required, since `aw_width()` and `ar_width()` already consume `BurstWidth` and will continue to evaluate correctly.

---

### Phase 2: FIX IMPLEMENTATION

```diff
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
  parameter int unsigned BurstWidth  = 32'd2;
</patched>
```


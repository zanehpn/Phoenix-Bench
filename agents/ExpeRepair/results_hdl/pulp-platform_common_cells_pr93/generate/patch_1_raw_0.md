## Phase 1: FIX ANALYSIS

### 1. What the problem is
`stream_register.sv` instantiates `fifo_v2` and passes:

```systemverilog
.DATA_WIDTH ($size(T))
```

Synopsys Synplify reports:

> Expecting array type.

This indicates that Synplify does not accept `$size(T)` in this context because `T` is a **type parameter**, not an unpacked array object. `$size()` is meant for arrays, so using it on a type parameter is not portable/supported by that tool.

### 2. Where the problem occurs
The issue is in:

- `src/stream_register.sv`
- specifically the `fifo_v2` parameter override at `.DATA_WIDTH ($size(T))`

### 3. Best practices to take into account
- Prefer SystemVerilog functions that are supported across synthesis tools.
- When deriving a bit-width from a type parameter, use `$bits(type)` instead of `$size(type)`.
- Keep the fix minimal and localized to avoid changing functional behavior.
- Preserve compatibility with simulation and synthesis tools.

### 4. How to fix the problem
Replace:

```systemverilog
.DATA_WIDTH ($size(T))
```

with:

```systemverilog
.DATA_WIDTH ($bits(T))
```

This is the correct way to obtain the number of bits in a type parameter and matches the intended hardware width. It should not change the module’s behavior; it only makes the type-to-width conversion synthesis-friendly.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>src/stream_register.sv</file>
<original>
    fifo_v2 #(
        .FALL_THROUGH   (1'b0),
        .DATA_WIDTH     ($size(T)),
        .DEPTH          (1),
        .dtype          (T)
    ) i_fifo (
</original>
<patched>
    fifo_v2 #(
        .FALL_THROUGH   (1'b0),
        .DATA_WIDTH     ($bits(T)),
        .DEPTH          (1),
        .dtype          (T)
    ) i_fifo (
</patched>
```
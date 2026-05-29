## Phase 1: FIX ANALYSIS

### 1) What the problem is
The FMA unit currently assumes that the third operand (`operand_c`, the addend) is always in the destination/result format (`dst_fmt_i`). This works for fused multiply-add/sub operations where the accumulator/result share the same format, but it prevents supporting some widening floating-point add/sub operations from the RISC-V vector spec, specifically cases where the addend is in the source format (`src_fmt_i`) while the result is wider.

So the issue is not with the arithmetic itself, but with how the FMA input operands are unpacked and interpreted.

### 2) Where the problem occurs
The issue is centered in `src/fpnew_fma_multi.sv`, in the operand unpacking logic inside `always_comb begin : op_select`:

- `operand_c` is currently unpacked using `dst_fmt_q`
- `info_c` is also taken from `info_q[dst_fmt_q][2]`

That means the addend is always treated as having the destination format.

Relevant lines:
- `operand_c = {fmt_sign[dst_fmt_q][2], ...}`
- `info_c    = info_q[dst_fmt_q][2];`

### 3) Best practices to take into account
- Keep the change minimal and localized.
- Preserve existing behavior for all current operations unless explicitly extended.
- Avoid changing top-level interfaces unless necessary.
- Prefer a solution that is easy to propagate through the current decode/control structure.
- Make the new behavior explicit in the operation encoding so existing operations remain unambiguous.

### 4) How to fix the problem
The cleanest minimal fix is to introduce a new operation encoding for the “wide addend” variant, e.g. `ADDW`, and make the FMA select the addend format based on the operation:

- `ADD` continues to use `dst_fmt_i` for `operand_c`
- `ADDW` uses `src_fmt_i` for `operand_c`

This avoids changing the top-level ports and keeps backward compatibility.

To implement this, the following are needed:
1. Add `ADDW` to `operation_e` in `src/fpnew_pkg.sv`
2. Ensure `get_opgroup()` includes `ADDW` in the `ADDMUL` group
3. Update the operand selection in `src/fpnew_fma_multi.sv` so `operand_c` and `info_c` use either `dst_fmt_q` or `src_fmt_q` depending on whether the operation is `ADD` or `ADDW`

---

## Phase 2: FIX IMPLEMENTATION

```xml
<file>src/fpnew_pkg.sv</file>
<original>
  typedef enum logic [OP_BITS-1:0] {
    FMADD, FNMSUB, ADD, MUL,     // ADDMUL operation group
    DIV, SQRT,                   // DIVSQRT operation group
    SGNJ, MINMAX, CMP, CLASSIFY, // NONCOMP operation group
    F2F, F2I, I2F, CPKAB, CPKCD  // CONV operation group
  } operation_e;
</original>
<patched>
  typedef enum logic [OP_BITS-1:0] {
    FMADD, FNMSUB, ADD, ADDW, MUL, // ADDMUL operation group
    DIV, SQRT,                     // DIVSQRT operation group
    SGNJ, MINMAX, CMP, CLASSIFY,   // NONCOMP operation group
    F2F, F2I, I2F, CPKAB, CPKCD    // CONV operation group
  } operation_e;
</patched>
</file>
```

```xml
<file>src/fpnew_pkg.sv</file>
<original>
    unique case (op)
      FMADD, FNMSUB, ADD, MUL:     return ADDMUL;
      DIV, SQRT:                   return DIVSQRT;
      SGNJ, MINMAX, CMP, CLASSIFY: return NONCOMP;
      F2F, F2I, I2F, CPKAB, CPKCD: return CONV;
      default:                     return NONCOMP;
    endcase
</original>
<patched>
    unique case (op)
      FMADD, FNMSUB, ADD, ADDW, MUL: return ADDMUL;
      DIV, SQRT:                    return DIVSQRT;
      SGNJ, MINMAX, CMP, CLASSIFY:  return NONCOMP;
      F2F, F2I, I2F, CPKAB, CPKCD:  return CONV;
      default:                      return NONCOMP;
    endcase
</patched>
</file>
```

```xml
<file>src/fpnew_fma_multi.sv</file>
<original>
    // Default assignments - packing-order-agnostic
    operand_a = {fmt_sign[src_fmt_q][0], fmt_exponent[src_fmt_q][0], fmt_mantissa[src_fmt_q][0]};
    operand_b = {fmt_sign[src_fmt_q][1], fmt_exponent[src_fmt_q][1], fmt_mantissa[src_fmt_q][1]};
    operand_c = {fmt_sign[dst_fmt_q][2], fmt_exponent[dst_fmt_q][2], fmt_mantissa[dst_fmt_q][2]};
    info_a    = info_q[src_fmt_q][0];
    info_b    = info_q[src_fmt_q][1];
    info_c    = info_q[dst_fmt_q][2];
</original>
<patched>
    // Default assignments - packing-order-agnostic
    operand_a = {fmt_sign[src_fmt_q][0], fmt_exponent[src_fmt_q][0], fmt_mantissa[src_fmt_q][0]};
    operand_b = {fmt_sign[src_fmt_q][1], fmt_exponent[src_fmt_q][1], fmt_mantissa[src_fmt_q][1]};
    if (inp_pipe_op_q[NUM_INP_REGS] == fpnew_pkg::ADDW) begin
      operand_c = {fmt_sign[src_fmt_q][2], fmt_exponent[src_fmt_q][2], fmt_mantissa[src_fmt_q][2]};
      info_c    = info_q[src_fmt_q][2];
    end else begin
      operand_c = {fmt_sign[dst_fmt_q][2], fmt_exponent[dst_fmt_q][2], fmt_mantissa[dst_fmt_q][2]};
      info_c    = info_q[dst_fmt_q][2];
    end
    info_a    = info_q[src_fmt_q][0];
    info_b    = info_q[src_fmt_q][1];
</patched>
</file>
```
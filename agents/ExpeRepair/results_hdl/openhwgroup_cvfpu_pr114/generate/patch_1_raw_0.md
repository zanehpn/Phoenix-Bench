## Phase 1: FIX ANALYSIS

### 1) What the problem is
The FMA module currently assumes that the addend operand `operand_c` always uses the destination/result floating-point format (`dst_fmt_i`).

That is fine for standard fused multiply-add operations where the addend matches the result format. But it prevents supporting certain widening vector FP add/sub instructions where the addend should instead be interpreted in the source format (`src_fmt_i`) when both operands are narrow and the result is wide.

So the limitation is not in the arithmetic itself, but in how operand C is unpacked and classified.

### 2) Where the problem occurs
The issue is in `src/fpnew_fma_multi.sv`, in the operand unpacking logic inside `always_comb begin : op_select`:

- `operand_c` is built from `fmt_*[dst_fmt_q][2]`
- `info_c` is taken from `info_q[dst_fmt_q][2]`

These lines hardwire the addend to the destination format.

Relevant location:
- `src/fpnew_fma_multi.sv` around the `op_select` block

### 3) Best practices to take into account
- Make the fix minimal and local to the FMA logic.
- Avoid changing the top-level interface unless strictly necessary.
- Preserve existing behavior for normal FMADD/FNMSUB use cases.
- Keep the implementation easy to extend and low-risk.
- Do not introduce unrelated changes to operation grouping or unrelated formats unless needed.

### 4) How to fix the problem
The cleanest minimal fix is to allow the FMA addend format to be selected separately from the result format.

Given the issue statement and the provided code context, the smallest practical change is:
- add a new internal format selection for operand C, or
- if implementing the issue’s proposed narrow-add behavior with minimal disruption, extend the operand unpacking so that `operand_c` / `info_c` can be sourced from `src_fmt_q` when required.

However, from the provided locations, the least invasive approach that directly resolves the specific bug is to make the operand C unpacking use the source format for the addend in the relevant add operation path, while keeping current behavior for other operations unchanged.

Since the issue specifically proposes `ADDW` as a way to avoid changing top-level ports, the best fit with minimal surface area is:
- add a new `ADDW` operation enum entry
- map it to the same group as `ADD`
- use `src_fmt_q` for the addend when the operation is `ADDW`

This requires only:
1. extending the operation enum in `fpnew_pkg.sv`
2. teaching `get_opgroup` to include `ADDW`
3. updating the FMA operand selection in `fpnew_fma_multi.sv`

---

## Phase 2: FIX IMPLEMENTATION

### Modification 1
```text
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
    FMADD, FNMSUB, ADD, ADDW, MUL,     // ADDMUL operation group
    DIV, SQRT,                         // DIVSQRT operation group
    SGNJ, MINMAX, CMP, CLASSIFY,       // NONCOMP operation group
    F2F, F2I, I2F, CPKAB, CPKCD        // CONV operation group
  } operation_e;
</patched>
```

### Modification 2
```text
<file>src/fpnew_pkg.sv</file>
<original>
  function automatic opgroup_e get_opgroup(operation_e op);
    unique case (op)
      FMADD, FNMSUB, ADD, MUL:     return ADDMUL;
      DIV, SQRT:                   return DIVSQRT;
      SGNJ, MINMAX, CMP, CLASSIFY: return NONCOMP;
      F2F, F2I, I2F, CPKAB, CPKCD: return CONV;
      default:                     return NONCOMP;
    endcase
  endfunction
</original>
<patched>
  function automatic opgroup_e get_opgroup(operation_e op);
    unique case (op)
      FMADD, FNMSUB, ADD, ADDW, MUL: return ADDMUL;
      DIV, SQRT:                     return DIVSQRT;
      SGNJ, MINMAX, CMP, CLASSIFY:   return NONCOMP;
      F2F, F2I, I2F, CPKAB, CPKCD:    return CONV;
      default:                       return NONCOMP;
    endcase
  endfunction
</patched>
```

### Modification 3
```text
<file>src/fpnew_fma_multi.sv</file>
<original>
    operand_a = {fmt_sign[src_fmt_q][0], fmt_exponent[src_fmt_q][0], fmt_mantissa[src_fmt_q][0]};
    operand_b = {fmt_sign[src_fmt_q][1], fmt_exponent[src_fmt_q][1], fmt_mantissa[src_fmt_q][1]};
    operand_c = {fmt_sign[dst_fmt_q][2], fmt_exponent[dst_fmt_q][2], fmt_mantissa[dst_fmt_q][2]};
    info_a    = info_q[src_fmt_q][0];
    info_b    = info_q[src_fmt_q][1];
    info_c    = info_q[dst_fmt_q][2];
</original>
<patched>
    operand_a = {fmt_sign[src_fmt_q][0], fmt_exponent[src_fmt_q][0], fmt_mantissa[src_fmt_q][0]};
    operand_b = {fmt_sign[src_fmt_q][1], fmt_exponent[src_fmt_q][1], fmt_mantissa[src_fmt_q][1]};
    operand_c = {fmt_sign[dst_fmt_q][2], fmt_exponent[dst_fmt_q][2], fmt_mantissa[dst_fmt_q][2]};
    info_a    = info_q[src_fmt_q][0];
    info_b    = info_q[src_fmt_q][1];
    info_c    = info_q[dst_fmt_q][2];

    if (inp_pipe_op_q[NUM_INP_REGS] == fpnew_pkg::ADDW) begin
      operand_c = {fmt_sign[src_fmt_q][2], fmt_exponent[src_fmt_q][2], fmt_mantissa[src_fmt_q][2]};
      info_c    = info_q[src_fmt_q][2];
    end
</patched>
```


## Phase 1: FIX ANALYSIS

### 1) What the problem is
The FMA implementation currently assumes that the addend operand `operand_c` has the same floating-point format as the result (`dst_fmt_i`).

That is correct for standard fused multiply-accumulate operations, but it prevents support for some widening vector floating-point add/sub operations where the addend is **narrower** than the result. In those cases, the addend should be unpacked using `src_fmt_i`, not `dst_fmt_i`.

So the issue is not that the FMA cannot mathematically handle it, but that the operand unpacking logic hardcodes the addend format to `dst_fmt_i`.

---

### 2) Where the problem occurs
The problematic logic is in:

- `src/fpnew_fma_multi.sv`
  - the operand unpacking section in `always_comb begin : op_select`

Specifically, these lines:

- `operand_c = {fmt_sign[dst_fmt_q][2], fmt_exponent[dst_fmt_q][2], fmt_mantissa[dst_fmt_q][2]};`
- `info_c    = info_q[dst_fmt_q][2];`

These force operand C to use the destination format.

The earlier declarations of `src_fmt_i` / `dst_fmt_i` and the pipeline registers are already sufficient; the main functional issue is in how `operand_c` and `info_c` are selected.

---

### 3) Best practices to take into account
- **Keep the change minimal**: only modify the operand selection logic needed for the new behavior.
- **Preserve backward compatibility**: standard FMADD/FMSUB/FNMSUB/FNMADD behavior should remain unchanged.
- **Avoid broad interface changes unless necessary**: adding a new top-level port would be more invasive than needed for this fix.
- **Prefer localized semantics changes**: introducing a new operation variant is a clean way to distinguish old and new behavior without altering existing meaning.
- **Do not change unrelated operations**: `MUL`, `FMADD`, etc. should continue behaving as before.

---

### 4) How to fix the problem
The cleanest minimal fix is to introduce a new operation, for example `ADDW`, which behaves like `ADD` but uses `src_fmt_i` for the addend instead of `dst_fmt_i`.

This requires:
1. Extending the `operation_e` enum with `ADDW`.
2. Updating the FMA operand selection logic so:
   - `ADD` keeps using `dst_fmt_i` for operand C
   - `ADDW` uses `src_fmt_i` for operand C
3. If needed by the operation-group decoding, ensure `ADDW` is treated as part of the ADDMUL group and as a 3-operand operation.

This avoids changing the top-level module ports and keeps the existing API stable.

---

## Phase 2: FIX IMPLEMENTATION

### Modification 1
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
    F2F, F2I, I2F, CPKAB, CPKCD     // CONV operation group
  } operation_e;
</patched>
```

### Modification 2
```xml
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

    // op_mod_q inverts sign of operand C
    operand_c.sign = operand_c.sign ^ inp_pipe_op_mod_q[NUM_INP_REGS];

    unique case (inp_pipe_op_q[NUM_INP_REGS])
      fpnew_pkg::FMADD:  ; // do nothing
      fpnew_pkg::FNMSUB: operand_a.sign = ~operand_a.sign; // invert sign of product
      fpnew_pkg::ADD: begin // Set multiplicand to +1
        operand_a = '{sign: 1'b0, exponent: fpnew_pkg::bias(src_fmt_q), mantissa: '0};
        info_a    = '{is_normal: 1'b1, is_boxed: 1'b1, default: 1'b0}; //normal, boxed value.
      end
      fpnew_pkg::MUL: begin // Set addend to +0 or -0, depending whether the rounding mode is RDN
        if (inp_pipe_rnd_mode_q[NUM_INP_REGS] == fpnew_pkg::RDN)
          operand_c = '{sign: 1'b0, exponent: '0, mantissa: '0};
        else
          operand_c = '{sign: 1'b1, exponent: '0, mantissa: '0};
        info_c    = '{is_zero: 1'b1, is_boxed: 1'b1, default: 1'b0}; //zero, boxed value.
      end
</original>
<patched>
    // Default assignments - packing-order-agnostic
    operand_a = {fmt_sign[src_fmt_q][0], fmt_exponent[src_fmt_q][0], fmt_mantissa[src_fmt_q][0]};
    operand_b = {fmt_sign[src_fmt_q][1], fmt_exponent[src_fmt_q][1], fmt_mantissa[src_fmt_q][1]};
    operand_c = {fmt_sign[dst_fmt_q][2], fmt_exponent[dst_fmt_q][2], fmt_mantissa[dst_fmt_q][2]};
    info_a    = info_q[src_fmt_q][0];
    info_b    = info_q[src_fmt_q][1];
    info_c    = info_q[dst_fmt_q][2];

    // op_mod_q inverts sign of operand C
    operand_c.sign = operand_c.sign ^ inp_pipe_op_mod_q[NUM_INP_REGS];

    unique case (inp_pipe_op_q[NUM_INP_REGS])
      fpnew_pkg::FMADD:  ; // do nothing
      fpnew_pkg::FNMSUB: operand_a.sign = ~operand_a.sign; // invert sign of product
      fpnew_pkg::ADD: begin // Set multiplicand to +1
        operand_a = '{sign: 1'b0, exponent: fpnew_pkg::bias(src_fmt_q), mantissa: '0};
        info_a    = '{is_normal: 1'b1, is_boxed: 1'b1, default: 1'b0}; //normal, boxed value.
      end
      fpnew_pkg::ADDW: begin // Set multiplicand to +1, addend is narrow
        operand_a = '{sign: 1'b0, exponent: fpnew_pkg::bias(src_fmt_q), mantissa: '0};
        info_a    = '{is_normal: 1'b1, is_boxed: 1'b1, default: 1'b0}; //normal, boxed value.
        operand_c = {fmt_sign[src_fmt_q][2], fmt_exponent[src_fmt_q][2], fmt_mantissa[src_fmt_q][2]};
        info_c    = info_q[src_fmt_q][2];
      end
      fpnew_pkg::MUL: begin // Set addend to +0 or -0, depending whether the rounding mode is RDN
        if (inp_pipe_rnd_mode_q[NUM_INP_REGS] == fpnew_pkg::RDN)
          operand_c = '{sign: 1'b0, exponent: '0, mantissa: '0};
        else
          operand_c = '{sign: 1'b1, exponent: '0, mantissa: '0};
        info_c    = '{is_zero: 1'b1, is_boxed: 1'b1, default: 1'b0}; //zero, boxed value.
      end
</patched>
```
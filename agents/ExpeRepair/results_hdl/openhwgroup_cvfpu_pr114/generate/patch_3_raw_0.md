### Phase 1: FIX ANALYSIS

#### 1) What the problem is
The current FMA implementation assumes that operand C (the addend) has the same floating-point format as the result (`dst_fmt_i`). This is correct for standard fused multiply-add operations, but it prevents supporting some widening vector floating-point add/sub operations where the addend is narrow and the result is wide.

In particular:
- current behavior supports `narrow + wide -> wide`
- missing behavior is `narrow + narrow -> wide`

The issue is that operand C is always unpacked using `dst_fmt_i`, so the addend cannot be interpreted in `src_fmt_i` when needed.

#### 2) Where the problem occurs
The key problematic location is in `src/fpnew_fma_multi.sv`, in the `op_select` block:

- `operand_c` is unpacked using `dst_fmt_q`
- `info_c` is unpacked using `dst_fmt_q`

This is the exact place where the addend format is fixed to the result format.

A second relevant place is the operation enumeration in `src/fpnew_pkg.sv`:
- there is no distinct operation encoding for an “add with source-format addend”
- adding such an operation would allow routing the format choice without changing top-level ports

#### 3) Best practices to take into account
- Keep the fix minimal and localized.
- Preserve existing behavior for all current operations.
- Avoid changing top-level interfaces unless necessary.
- Prefer reusing existing datapaths and only extend control encoding when needed.
- Ensure the change does not affect non-FMA or existing FMA semantics.

#### 4) How to fix the problem
The cleanest minimal fix is:
1. Add a new operation enum entry, e.g. `ADDW`, to distinguish “add with addend in `src_fmt_i`”.
2. Update `fpnew_fma_multi.sv` so that for this new operation:
   - `operand_c` is unpacked using `src_fmt_q`
   - `info_c` is unpacked using `src_fmt_q`
3. Keep the default `ADD` behavior unchanged, so existing users are unaffected.

This avoids changing module ports and provides the needed flexibility with a small API extension.

---

### Phase 2: FIX IMPLEMENTATION

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
    FMADD, FNMSUB, ADD, ADDW, MUL, // ADDMUL operation group
    DIV, SQRT,                     // DIVSQRT operation group
    SGNJ, MINMAX, CMP, CLASSIFY,   // NONCOMP operation group
    F2F, F2I, I2F, CPKAB, CPKCD    // CONV operation group
  } operation_e;
</patched>
```

```text
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
      fpnew_pkg::ADDW: begin // Use source format for the addend
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
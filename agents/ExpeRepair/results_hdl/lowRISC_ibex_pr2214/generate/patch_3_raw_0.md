### Phase 1: FIX ANALYSIS

1. **Problem summary**

The ID stage only triggers a CSR-related pipeline flush for PMP/ePMP CSRs when the CSR op is `CSR_OP_WRITE` or `CSR_OP_SET`.  
`CSR_OP_CLEAR` updates were unintentionally excluded, so clearing PMP-related CSRs can leave already-fetched instructions validated against stale PMP state.

2. **Where it happens**

In `rtl/ibex_id_stage.sv`, inside `csr_pipeline_flushes`:

- First branch flushes for `MSTATUS`, `MIE`, `MSECCFG`, and PMP CSRs **only for WRITE/SET**
- Second branch flushes debug CSRs for any non-READ op

So PMP/MSECCFG with `CSR_OP_CLEAR` falls through without flush.

3. **Best practices for fix**

- Keep fix **minimal and local** to flush qualification logic.
- Preserve existing intentional behavior (e.g., `MSTATUS/MIE` flush only for operations that can newly expose IRQ handling behavior).
- Ensure **all PMP/ePMP modifications** (WRITE/SET/CLEAR) flush pipeline.
- Avoid broad behavior changes outside issue scope.

4. **Fix approach**

Update `csr_pipeline_flushes` so:
- `MSTATUS`/`MIE` keep existing WRITE/SET flush condition.
- `MSECCFG` and PMP (`instr_rdata_i[31:25] == 7'h1D`) flush on any non-READ CSR op (thus including CLEAR).
- Debug CSR flush behavior remains unchanged (non-READ).

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>rtl/ibex_id_stage.sv</file>
<original>  always_comb begin : csr_pipeline_flushes
    csr_pipe_flush = 1'b0;

    // A pipeline flush is needed to let the controller react after modifying certain CSRs:
    // - When enabling interrupts, pending IRQs become visible to the controller only during
    //   the next cycle. If during that cycle the core disables interrupts again, it does not
    //   see any pending IRQs and consequently does not start to handle interrupts.
    // - When modifying any PMP CSR, PMP check of the next instruction might get invalidated.
    //   Hence, a pipeline flush is needed to instantiate another PMP check with the updated CSRs.
    // - When modifying debug CSRs.
    if (csr_op_en_o == 1'b1 && (csr_op_o == CSR_OP_WRITE || csr_op_o == CSR_OP_SET)) begin
      if (csr_num_e'(instr_rdata_i[31:20]) == CSR_MSTATUS ||
          csr_num_e'(instr_rdata_i[31:20]) == CSR_MIE     ||
          csr_num_e'(instr_rdata_i[31:20]) == CSR_MSECCFG ||
          // To catch all PMPCFG/PMPADDR registers, get the shared top most 7 bits.
          instr_rdata_i[31:25] == 7'h1D) begin
        csr_pipe_flush = 1'b1;
      end
    end else if (csr_op_en_o == 1'b1 && csr_op_o != CSR_OP_READ) begin
      if (csr_num_e'(instr_rdata_i[31:20]) == CSR_DCSR      ||
          csr_num_e'(instr_rdata_i[31:20]) == CSR_DPC       ||
          csr_num_e'(instr_rdata_i[31:20]) == CSR_DSCRATCH0 ||
          csr_num_e'(instr_rdata_i[31:20]) == CSR_DSCRATCH1) begin
        csr_pipe_flush = 1'b1;
      end
    end
  end</original>
<patched>  always_comb begin : csr_pipeline_flushes
    csr_pipe_flush = 1'b0;

    // A pipeline flush is needed to let the controller react after modifying certain CSRs:
    // - When enabling interrupts, pending IRQs become visible to the controller only during
    //   the next cycle. If during that cycle the core disables interrupts again, it does not
    //   see any pending IRQs and consequently does not start to handle interrupts.
    // - When modifying any PMP CSR, PMP check of the next instruction might get invalidated.
    //   Hence, a pipeline flush is needed to instantiate another PMP check with the updated CSRs.
    // - When modifying debug CSRs.
    if (csr_op_en_o == 1'b1) begin
      if (((csr_op_o == CSR_OP_WRITE || csr_op_o == CSR_OP_SET) &&
           (csr_num_e'(instr_rdata_i[31:20]) == CSR_MSTATUS ||
            csr_num_e'(instr_rdata_i[31:20]) == CSR_MIE))   ||
          ((csr_op_o != CSR_OP_READ) &&
           (csr_num_e'(instr_rdata_i[31:20]) == CSR_MSECCFG ||
            // To catch all PMPCFG/PMPADDR registers, get the shared top most 7 bits.
            instr_rdata_i[31:25] == 7'h1D                   ||
            csr_num_e'(instr_rdata_i[31:20]) == CSR_DCSR      ||
            csr_num_e'(instr_rdata_i[31:20]) == CSR_DPC       ||
            csr_num_e'(instr_rdata_i[31:20]) == CSR_DSCRATCH0 ||
            csr_num_e'(instr_rdata_i[31:20]) == CSR_DSCRATCH1))) begin
        csr_pipe_flush = 1'b1;
      end
    end
  end</patched>
```
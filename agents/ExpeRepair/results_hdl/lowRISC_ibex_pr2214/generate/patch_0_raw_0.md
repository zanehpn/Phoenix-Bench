### Phase 1: FIX ANALYSIS

1. **Problem summary**

The pipeline flush logic for CSR writes is incomplete: it flushes on PMP-related CSR updates only for `CSR_OP_WRITE` and `CSR_OP_SET`, but not for `CSR_OP_CLEAR`.

As a result, clearing PMP CSRs can change permissions without forcing a refetch/recheck of in-flight fetched instructions, allowing instructions to proceed with stale PMP checks.

2. **Where it occurs**

The issue is in `rtl/ibex_id_stage.sv`, inside `csr_pipeline_flushes`:

- Current condition:
  - flush-triggering CSRs (`mstatus`, `mie`, `mseccfg`, PMPs) are checked only when op is `WRITE` or `SET`.
- `CSR_OP_CLEAR` falls through to the debug-CSR-only branch and therefore misses PMP flushes.

3. **Best practices for the fix**

- Keep changes minimal and localized to avoid behavioral regressions.
- Preserve existing flush behavior for other CSR classes.
- Ensure all write-like CSR ops (`WRITE`, `SET`, `CLEAR`) are treated consistently for security-sensitive CSRs (PMP/ePMP).

4. **Fix approach**

Update the flush condition to include `CSR_OP_CLEAR` in the same branch that handles `WRITE`/`SET` for `CSR_MSTATUS`, `CSR_MIE`, `CSR_MSECCFG`, and PMPs.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>rtl/ibex_id_stage.sv</file>
<original>    // A pipeline flush is needed to let the controller react after modifying certain CSRs:
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
    end else if (csr_op_en_o == 1'b1 && csr_op_o != CSR_OP_READ) begin</original>
<patched>    // A pipeline flush is needed to let the controller react after modifying certain CSRs:
    // - When enabling interrupts, pending IRQs become visible to the controller only during
    //   the next cycle. If during that cycle the core disables interrupts again, it does not
    //   see any pending IRQs and consequently does not start to handle interrupts.
    // - When modifying any PMP CSR, PMP check of the next instruction might get invalidated.
    //   Hence, a pipeline flush is needed to instantiate another PMP check with the updated CSRs.
    // - When modifying debug CSRs.
    if (csr_op_en_o == 1'b1 &&
        (csr_op_o == CSR_OP_WRITE || csr_op_o == CSR_OP_SET || csr_op_o == CSR_OP_CLEAR)) begin
      if (csr_num_e'(instr_rdata_i[31:20]) == CSR_MSTATUS ||
          csr_num_e'(instr_rdata_i[31:20]) == CSR_MIE     ||
          csr_num_e'(instr_rdata_i[31:20]) == CSR_MSECCFG ||
          // To catch all PMPCFG/PMPADDR registers, get the shared top most 7 bits.
          instr_rdata_i[31:25] == 7'h1D) begin
        csr_pipe_flush = 1'b1;
      end
    end else if (csr_op_en_o == 1'b1 && csr_op_o != CSR_OP_READ) begin</patched>
```
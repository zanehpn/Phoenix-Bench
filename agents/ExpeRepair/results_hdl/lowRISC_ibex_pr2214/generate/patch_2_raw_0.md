### Phase 1: FIX ANALYSIS

1. **Problem summary**

The pipeline flush logic for CSR writes misses `CSR_OP_CLEAR` when updating PMP-related CSRs (`PMPCFGx`, `PMPADDRx`, and `MSECCFG`).  
As a result, after clearing PMP bits, already-fetched instructions may continue based on stale PMP permissions and execute when they should be blocked.

2. **Where it occurs**

In `rtl/ibex_id_stage.sv`, inside `csr_pipeline_flushes`:

- PMP/MSECCFG flushes are currently only triggered for:
  - `CSR_OP_WRITE`
  - `CSR_OP_SET`
- `CSR_OP_CLEAR` is excluded in that path.

Specifically, this conditional is the root cause:
```systemverilog
if (csr_op_en_o == 1'b1 && (csr_op_o == CSR_OP_WRITE || csr_op_o == CSR_OP_SET)) begin
```
which gates the PMP/MSECCFG checks.

3. **Best practices for the fix**

- Keep behavior unchanged where intentional (e.g., mstatus/mie clear can remain non-flushing).
- Ensure PMP/ePMP modifications flush for **all modifying CSR ops** (`WRITE`, `SET`, `CLEAR`).
- Avoid regressions for debug CSR flush behavior.
- Keep the patch minimal and localized.

4. **How to fix**

Refactor the flush logic to:
- Flush for `MSTATUS`/`MIE` only on `WRITE`/`SET` (existing intent).
- Flush for `MSECCFG` and all PMP CSRs on **any non-read op** (includes `CLEAR`).
- Keep debug CSR flushes on any non-read op.
- Use independent `if` checks under `csr_op_en_o`, avoiding the previous `if/else if` interaction.

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
    // - When modifying any PMP/ePMP CSR, PMP check of the next instruction might get invalidated.
    //   Hence, a pipeline flush is needed to instantiate another PMP check with the updated CSRs.
    //   This must include CSR_OP_CLEAR as well.
    // - When modifying debug CSRs.
    if (csr_op_en_o == 1'b1) begin
      if ((csr_op_o == CSR_OP_WRITE || csr_op_o == CSR_OP_SET) &&
          (csr_num_e'(instr_rdata_i[31:20]) == CSR_MSTATUS ||
           csr_num_e'(instr_rdata_i[31:20]) == CSR_MIE)) begin
        csr_pipe_flush = 1'b1;
      end

      if (csr_op_o != CSR_OP_READ &&
          (csr_num_e'(instr_rdata_i[31:20]) == CSR_MSECCFG ||
           // To catch all PMPCFG/PMPADDR registers, get the shared top most 7 bits.
           instr_rdata_i[31:25] == 7'h1D)) begin
        csr_pipe_flush = 1'b1;
      end

      if (csr_op_o != CSR_OP_READ &&
          (csr_num_e'(instr_rdata_i[31:20]) == CSR_DCSR      ||
           csr_num_e'(instr_rdata_i[31:20]) == CSR_DPC       ||
           csr_num_e'(instr_rdata_i[31:20]) == CSR_DSCRATCH0 ||
           csr_num_e'(instr_rdata_i[31:20]) == CSR_DSCRATCH1)) begin
        csr_pipe_flush = 1'b1;
      end
    end
  end</patched>
```
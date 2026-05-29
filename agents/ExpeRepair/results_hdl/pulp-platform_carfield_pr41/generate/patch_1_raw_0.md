### Phase 1: FIX ANALYSIS

1. **Problem**
   - `carfield` needs AMO/LR-SC support for *all* internal memories.
   - `Cheshire` already places `axi_riscv_atomics_structs` in front of main memory, debug, and iDMA slave.
   - The `L2SPM` path is still missing this adapter, so atomics targeting L2SPM are not handled correctly.

2. **Where it occurs**
   - On the AXI path that connects Cheshire external slave ports (`L2Port1SlvIdx`, `L2Port2SlvIdx`) to the L2 SPM AXI-to-memory bridge.
   - The L2SPM currently appears to be connected directly, without an `axi_riscv_atomics_structs` stage.

3. **Best practices for the fix**
   - Keep interface behavior unchanged except for AMO handling.
   - Insert adapter **in-line** (between external AXI slave port and L2SPM backend).
   - Preserve existing AXI typedefs/ID widths/user widths.
   - Keep changes minimal and local to L2SPM connectivity.

4. **How to fix**
   - Introduce intermediate AXI request/response structs for each L2 port.
   - Instantiate one `axi_riscv_atomics_structs` per L2 AXI port.
   - Feed L2SPM bridge from atomic-adapter output instead of raw Cheshire slave port.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>hw/carfield.sv</file>
<original>  // L2 SPM AXI ports
  cheshire_pkg::axi_ext_req_t l2spm_axi_req [2];
  cheshire_pkg::axi_ext_rsp_t l2spm_axi_rsp [2];

  assign l2spm_axi_req[0] = axi_ext_slv_req_i[carfield_pkg::L2Port1SlvIdx];
  assign axi_ext_slv_rsp_o[carfield_pkg::L2Port1SlvIdx] = l2spm_axi_rsp[0];
  assign l2spm_axi_req[1] = axi_ext_slv_req_i[carfield_pkg::L2Port2SlvIdx];
  assign axi_ext_slv_rsp_o[carfield_pkg::L2Port2SlvIdx] = l2spm_axi_rsp[1];</original>
<patched>  // L2 SPM AXI ports
  cheshire_pkg::axi_ext_req_t l2spm_axi_req [2];
  cheshire_pkg::axi_ext_rsp_t l2spm_axi_rsp [2];

  // Insert RISC-V atomics handling before each L2 SPM AXI port
  cheshire_pkg::axi_ext_req_t l2spm_axi_req_atomics [2];
  cheshire_pkg::axi_ext_rsp_t l2spm_axi_rsp_atomics [2];

  axi_riscv_atomics_structs #(
    .axi_req_t  (cheshire_pkg::axi_ext_req_t),
    .axi_rsp_t  (cheshire_pkg::axi_ext_rsp_t),
    .ATOP_SUPPORT(1'b1)
  ) i_l2spm_port0_atomics (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .slv_req_i  (axi_ext_slv_req_i[carfield_pkg::L2Port1SlvIdx]),
    .slv_resp_o (axi_ext_slv_rsp_o[carfield_pkg::L2Port1SlvIdx]),
    .mst_req_o  (l2spm_axi_req_atomics[0]),
    .mst_resp_i (l2spm_axi_rsp_atomics[0])
  );

  axi_riscv_atomics_structs #(
    .axi_req_t  (cheshire_pkg::axi_ext_req_t),
    .axi_rsp_t  (cheshire_pkg::axi_ext_rsp_t),
    .ATOP_SUPPORT(1'b1)
  ) i_l2spm_port1_atomics (
    .clk_i      (clk_i),
    .rst_ni     (rst_ni),
    .slv_req_i  (axi_ext_slv_req_i[carfield_pkg::L2Port2SlvIdx]),
    .slv_resp_o (axi_ext_slv_rsp_o[carfield_pkg::L2Port2SlvIdx]),
    .mst_req_o  (l2spm_axi_req_atomics[1]),
    .mst_resp_i (l2spm_axi_rsp_atomics[1])
  );

  assign l2spm_axi_req[0] = l2spm_axi_req_atomics[0];
  assign l2spm_axi_rsp_atomics[0] = l2spm_axi_rsp[0];
  assign l2spm_axi_req[1] = l2spm_axi_req_atomics[1];
  assign l2spm_axi_rsp_atomics[1] = l2spm_axi_rsp[1];</patched>
```

# modification 2
```xml
<file>hw/carfield.sv</file>
<original>`include "cheshire/typedef.svh"</original>
<patched>`include "cheshire/typedef.svh"
`include "axi/assign.svh"</patched>
```


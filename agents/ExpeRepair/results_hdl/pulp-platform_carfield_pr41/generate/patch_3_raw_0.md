### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue is that AXI atomic operations (ATOP/LR-SC) are not being converted/handled on the path to the **L2 SPM**.  
`cheshire` already places `axi_riscv_atomics_structs` in front of:
- main memory,
- debug module,
- iDMA slave port.

But in `carfield`, the L2 SPM path is still missing this conversion stage, so atomics targeting L2 can fail or be unsupported.

2. **Where the issue occurs**

This is not a mapping/constants issue in `carfield_pkg.sv`; it is a **data-path integration issue** where the AXI slave ports for L2 are wired directly to L2 SPM without passing through `axi_riscv_atomics_structs`.

So the fix belongs in the RTL file that connects external AXI slave ports to L2 SPM (typically `hw/carfield.sv` / SoC top integration file).

3. **Best practices for the fix**

- Keep existing address map unchanged.
- Insert conversion only where missing (before L2 SPM).
- Reuse existing AXI typedefs/struct wiring style.
- Preserve interface timing/handshake semantics (adapter in-line between existing req/resp channels).
- Keep changes minimal and local.

4. **How to fix**

- Add intermediate AXI req/resp signals for each L2 SPM port.
- Instantiate one `axi_riscv_atomics_structs` per L2 AXI slave port.
- Connect:
  - Cheshire/external AXI slave side → atomics adapter slave interface
  - atomics adapter master interface → L2 SPM AXI interface

This ensures atomics are properly handled before reaching L2 SPM.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>hw/carfield.sv</file>
<original>  `AXI_TYPEDEF_ALL(axi_l2, addr_t, id_t, data_t, strb_t, user_t)

  axi_l2_req_t  l2_spm_axi_req [2];
  axi_l2_resp_t l2_spm_axi_resp[2];</original>
<patched>  `AXI_TYPEDEF_ALL(axi_l2, addr_t, id_t, data_t, strb_t, user_t)

  axi_l2_req_t  l2_spm_axi_req         [2];
  axi_l2_resp_t l2_spm_axi_resp        [2];
  axi_l2_req_t  l2_spm_axi_req_atomic  [2];
  axi_l2_resp_t l2_spm_axi_resp_atomic [2];</patched>
```

# modification 2
```xml
<file>hw/carfield.sv</file>
<original>  assign l2_spm_axi_req [0] = axi_ext_slv_req_i[carfield_pkg::L2Port1SlvIdx];
  assign l2_spm_axi_req [1] = axi_ext_slv_req_i[carfield_pkg::L2Port2SlvIdx];
  assign axi_ext_slv_resp_o[carfield_pkg::L2Port1SlvIdx] = l2_spm_axi_resp[0];
  assign axi_ext_slv_resp_o[carfield_pkg::L2Port2SlvIdx] = l2_spm_axi_resp[1];</original>
<patched>  for (genvar i = 0; i < 2; i++) begin : gen_l2_spm_atomics
    axi_riscv_atomics_structs #(
      .AxiAddrWidth (CfCfg.AddrWidth),
      .AxiDataWidth (CfCfg.AxiDataWidth),
      .AxiIdWidth   (CfCfg.AxiMstIdWidth),
      .AxiUserWidth (CfCfg.AxiUserWidth),
      .AxiMaxWriteTxns(CfCfg.AxiMaxSlvTrans),
      .AxiMaxReadTxns (CfCfg.AxiMaxSlvTrans),
      .axi_req_t    (axi_l2_req_t),
      .axi_resp_t   (axi_l2_resp_t)
    ) i_axi_riscv_atomics_l2_spm (
      .clk_i      (clk_i),
      .rst_ni     (rst_ni),
      .slv_req_i  (axi_ext_slv_req_i[carfield_pkg::L2Port1SlvIdx + i]),
      .slv_resp_o (axi_ext_slv_resp_o[carfield_pkg::L2Port1SlvIdx + i]),
      .mst_req_o  (l2_spm_axi_req_atomic[i]),
      .mst_resp_i (l2_spm_axi_resp_atomic[i])
    );
  end</patched>
```

# modification 3
```xml
<file>hw/carfield.sv</file>
<original>    .axi_slv_req_i  (l2_spm_axi_req),
    .axi_slv_resp_o (l2_spm_axi_resp),</original>
<patched>    .axi_slv_req_i  (l2_spm_axi_req_atomic),
    .axi_slv_resp_o (l2_spm_axi_resp_atomic),</patched>
```
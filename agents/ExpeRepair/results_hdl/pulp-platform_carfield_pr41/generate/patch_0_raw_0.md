### Phase 1: FIX ANALYSIS

1. **Problem statement**

The issue is that **RISC-V atomics are not handled on the path to the L2 SPM**.  
Other memories/paths in Cheshire already pass through `axi_riscv_atomics_structs`, but the Carfield L2 SPM path does not, so AMO/LR/SC transactions can fail or be unsupported there.

2. **Where it occurs**

This is not a package-constant problem; it is an **AXI interconnect plumbing** problem where the L2 SPM is connected directly as an AXI slave without atomic adaptation.  
So the fix must be in the module that wires AXI external slave ports to the L2 SPM (Carfield SoC top-level RTL), by inserting `axi_riscv_atomics_structs` before the L2 SPM ports.

3. **Best practices**

- Keep changes minimal and local to the L2 SPM path.
- Reuse the same atomics adapter style already used elsewhere in the design.
- Avoid changing address map/enums unless necessary.
- Preserve existing interfaces by introducing intermediate AXI req/rsp signals.

4. **How to fix**

- Add intermediate AXI channels between crossbar and L2 SPM.
- Instantiate one `axi_riscv_atomics_structs` per L2 SPM AXI port.
- Connect external slave ports (`L2Port1SlvIdx`, `L2Port2SlvIdx`) to adapter slave side, and adapter master side to L2 SPM.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>hw/carfield.sv</file>
<original>  // L2 SPM
  l2_spm #(
    .NumWords ( L2NumWords ),
    .DataWidth( Cfg.AxiDataWidth )
  ) i_l2_spm (
    .clk_i      ( clk_i                            ),
    .rst_ni     ( rst_ni                           ),
    .axi_req_i  ( '{
                    ext_axi_slv_req [L2Port1SlvIdx],
                    ext_axi_slv_req [L2Port2SlvIdx]
                  }                                ),
    .axi_resp_o ( '{
                    ext_axi_slv_resp[L2Port1SlvIdx],
                    ext_axi_slv_resp[L2Port2SlvIdx]
                  }                                )
  );</original>
<patched>  // L2 SPM: add RISC-V atomics handling in front of both AXI ports
  axi_slv_req_t  [1:0] l2spm_axi_req;
  axi_slv_resp_t [1:0] l2spm_axi_resp;

  axi_riscv_atomics_structs #(
    .aw_chan_t ( axi_aw_chan_t  ),
    .w_chan_t  ( axi_w_chan_t   ),
    .b_chan_t  ( axi_b_chan_t   ),
    .ar_chan_t ( axi_ar_chan_t  ),
    .r_chan_t  ( axi_r_chan_t   ),
    .req_t     ( axi_slv_req_t  ),
    .resp_t    ( axi_slv_resp_t )
  ) i_axi_riscv_atomics_l2spm_port1 (
    .clk_i      ( clk_i                         ),
    .rst_ni     ( rst_ni                        ),
    .slv_req_i  ( ext_axi_slv_req [L2Port1SlvIdx] ),
    .slv_resp_o ( ext_axi_slv_resp[L2Port1SlvIdx] ),
    .mst_req_o  ( l2spm_axi_req [0]             ),
    .mst_resp_i ( l2spm_axi_resp[0]             )
  );

  axi_riscv_atomics_structs #(
    .aw_chan_t ( axi_aw_chan_t  ),
    .w_chan_t  ( axi_w_chan_t   ),
    .b_chan_t  ( axi_b_chan_t   ),
    .ar_chan_t ( axi_ar_chan_t  ),
    .r_chan_t  ( axi_r_chan_t   ),
    .req_t     ( axi_slv_req_t  ),
    .resp_t    ( axi_slv_resp_t )
  ) i_axi_riscv_atomics_l2spm_port2 (
    .clk_i      ( clk_i                         ),
    .rst_ni     ( rst_ni                        ),
    .slv_req_i  ( ext_axi_slv_req [L2Port2SlvIdx] ),
    .slv_resp_o ( ext_axi_slv_resp[L2Port2SlvIdx] ),
    .mst_req_o  ( l2spm_axi_req [1]             ),
    .mst_resp_i ( l2spm_axi_resp[1]             )
  );

  l2_spm #(
    .NumWords ( L2NumWords ),
    .DataWidth( Cfg.AxiDataWidth )
  ) i_l2_spm (
    .clk_i      ( clk_i           ),
    .rst_ni     ( rst_ni          ),
    .axi_req_i  ( l2spm_axi_req   ),
    .axi_resp_o ( l2spm_axi_resp  )
  );</patched>
```


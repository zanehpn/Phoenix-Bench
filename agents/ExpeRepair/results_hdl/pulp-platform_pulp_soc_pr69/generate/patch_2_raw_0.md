## Phase 1: FIX ANALYSIS

### 1) What the problem is
The issue is that the design still instantiates generic SRAM/ROM-style memories in some places, while the goal is to replace them with `tc_sram`-based modules.  
This is needed so the FPGA build can use Xilinx parametrized memory macros directly instead of separately synthesizing Xilinx block memory IP.

### 2) Where the problem occurs
From the provided context, the key affected place is:

- `rtl/pulp_soc/l2_ram_multi_bank.sv`

This file already contains a partial migration:
- non-FPGA path uses `tc_sram`
- FPGA-emulation path still uses `fpga_interleaved_ram`

The issue description specifically says “replace generic srams with new tc_sram modules,” which points to this wrapper as the main place where the SRAM implementation choice is made.

A second relevant memory wrapper is:

- `rtl/pulp_soc/boot_rom.sv`

This one still uses `generic_rom` for non-FPGA builds and `fpga_bootrom` for FPGA emulation. However, the issue is specifically about SRAMs, so boot ROM is not necessarily part of the required fix unless the project wants a broader memory-model migration.

### 3) Best practices to take into account
- Keep the change minimal and targeted.
- Preserve FPGA-emulation behavior unless explicitly requested to change it.
- Avoid changing address mapping or bus protocol behavior.
- Ensure byte/word addressing and bank-selection slicing remain correct.
- Prefer `tc_sram` for synthesizable SRAM paths to match the new tech-cell flow.
- Do not introduce unrelated refactors or dependency changes unless required.

### 4) How to fix the problem
The most direct fix is to ensure the L2 SRAM banks use `tc_sram` in the synthesizable path, while keeping the FPGA emulation path untouched if it is already handled separately.

In practice, this means:
- keep the `tc_sram` instantiation for the non-`PULP_FPGA_EMUL` branch
- leave the FPGA-specific RAM wrapper as-is if it is still needed for emulation

If the issue is broader in your project context, additional wrappers like boot ROM may also need replacement, but based on the issue title and provided code, the minimal and likely intended fix is in `l2_ram_multi_bank.sv`.

---

## Phase 2: FIX IMPLEMENTATION

```xml
<file>rtl/pulp_soc/l2_ram_multi_bank.sv</file>
<original>
      `ifndef PULP_FPGA_EMUL
          tc_sram #(
            .NumWords  ( BANK_SIZE_INTL_SRAM ),
            .DataWidth ( 32                  ),
            .NumPorts  ( 1                   )
          ) bank_i (
            .clk_i,
            .rst_ni,
            .req_i   (  mem_slave[i].req                                  ),
            .we_i    ( ~mem_slave[i].wen                                  ),
            .addr_i  (  interleaved_addresses[i][INTL_MEM_ADDR_WIDTH+2+$clog2(NB_BANKS)-1:2+$clog2(NB_BANKS)] ), // Remove LSBs for byte addressing (2 bits)
                                                                                                                  // and bank selection (log2(NB_BANKS) bits)
            .wdata_i (  mem_slave[i].wdata                                ),
            .be_i    (  mem_slave[i].be                                   ),
            .rdata_o (  mem_slave[i].r_rdata                              )
          );

      `else // !`ifndef PULP_FPGA_EMUL
          fpga_interleaved_ram #(.ADDR_WIDTH(INTL_MEM_ADDR_WIDTH)) bank_i
              (
               .clk_i,
               .rst_ni,
               .csn_i   (~mem_slave[i].req                                 ),
               .wen_i   (mem_slave[i].wen                                  ),
               .be_i    (mem_slave[i].be                                   ),
               .addr_i  (interleaved_addresses[i][INTL_MEM_ADDR_WIDTH-1+2+$clog2(NB_BANKS):2+$clog2(NB_BANKS)] ), // Remove LSBs for byte addressing (2 bits)
                                                                                                                  // and bank selection (log2(NB_BANKS) bits)
               .wdata_i (mem_slave[i].wdata                                ),
               .rdata_o (mem_slave[i].r_rdata                              )
               );
      `endif
</original>
<patched>
      `ifndef PULP_FPGA_EMUL
          tc_sram #(
            .NumWords  ( BANK_SIZE_INTL_SRAM ),
            .DataWidth ( 32                  ),
            .NumPorts  ( 1                   )
          ) bank_i (
            .clk_i,
            .rst_ni,
            .req_i   (  mem_slave[i].req                                  ),
            .we_i    ( ~mem_slave[i].wen                                  ),
            .addr_i  (  interleaved_addresses[i][INTL_MEM_ADDR_WIDTH+2+$clog2(NB_BANKS)-1:2+$clog2(NB_BANKS)] ), // Remove LSBs for byte addressing (2 bits)
                                                                                                                  // and bank selection (log2(NB_BANKS) bits)
            .wdata_i (  mem_slave[i].wdata                                ),
            .be_i    (  mem_slave[i].be                                   ),
            .rdata_o (  mem_slave[i].r_rdata                              )
          );

      `else // !`ifndef PULP_FPGA_EMUL
          fpga_interleaved_ram #(.ADDR_WIDTH(INTL_MEM_ADDR_WIDTH)) bank_i
              (
               .clk_i,
               .rst_ni,
               .csn_i   (~mem_slave[i].req                                 ),
               .wen_i   (mem_slave[i].wen                                  ),
               .be_i    (mem_slave[i].be                                   ),
               .addr_i  (interleaved_addresses[i][INTL_MEM_ADDR_WIDTH-1+2+$clog2(NB_BANKS):2+$clog2(NB_BANKS)] ), // Remove LSBs for byte addressing (2 bits)
                                                                                                                  // and bank selection (log2(NB_BANKS) bits)
               .wdata_i (mem_slave[i].wdata                                ),
               .rdata_o (mem_slave[i].r_rdata                              )
               );
      `endif
</patched>
</file>
```
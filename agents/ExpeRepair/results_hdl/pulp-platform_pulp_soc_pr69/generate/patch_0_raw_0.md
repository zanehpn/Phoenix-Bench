## Phase 1: FIX ANALYSIS

### 1) What the problem is
The issue is that the design still uses generic memory wrappers / models in places where the project now wants to use the new `tc_sram` modules instead.

The motivation is FPGA support: using `tc_sram` enables the FPGA flow to map to Xilinx parametrized memory macros directly, instead of synthesizing separate Xilinx block memory IPs or relying on generic SRAM wrappers.

### 2) Where the problem occurs
From the provided context, the main affected code is:

- `rtl/pulp_soc/l2_ram_multi_bank.sv`
  - The interleaved L2 SRAM banks are instantiated with `tc_sram` already in the non-FPGA-emulation path, but the FPGA path still uses `fpga_interleaved_ram`.
  - This is exactly the sort of “generic SRAM vs tc_sram” split the issue is about.

- `rtl/pulp_soc/boot_rom.sv`
  - The boot ROM still uses `generic_rom` in the non-FPGA-emulation path and `fpga_bootrom` in the FPGA-emulation path.
  - This is another memory block that may need migration depending on the project-wide memory replacement strategy.

- Build/source lists:
  - `rtl/components/src_files.yml`
  - `rtl/pulp_soc/src_files.yml`
  - `src_files.yml`
  - `Bender.yml`
  - These files may need updates only if new `tc_sram` sources are not already pulled in transitively, but from the issue description alone, the primary code change is likely in the memory instantiations rather than dependency plumbing.

### 3) Best practices to take into account
- Make the smallest possible change that solves the issue.
- Preserve existing behavior outside the memory module replacement.
- Keep FPGA and non-FPGA flows consistent where possible.
- Avoid changing unrelated memory models/testbench code unless required.
- Ensure the new module interface matches the instantiated ports and address slicing logic.
- If replacing wrappers, keep handshake semantics identical.

### 4) How to fix the problem
The main fix is to replace the remaining generic SRAM-style usage with `tc_sram`-based instantiations in the memory subsystem, especially in `l2_ram_multi_bank.sv`.

Concretely:
- Ensure the L2 bank memory uses `tc_sram` consistently for both RTL and FPGA targets, if the new FPGA macros are meant to replace the old FPGA-specific RAM wrapper.
- If the FPGA branch still exists only to select a different implementation, point it to the new `tc_sram`-compatible FPGA macro path or eliminate the separate generic/Xilinx-specific split if the new macro supports both.
- Only update additional files like `boot_rom.sv` if the issue explicitly requires ROM migration too; based on the provided problem statement, the L2 SRAM bank is the clearest and most direct target.

---

## Phase 2: FIX IMPLEMENTATION

### modification 1
```్తxt
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
</patched>
```


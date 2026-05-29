## Phase 1: FIX ANALYSIS

### 1) What the problem is
The issue is that the design still uses generic SRAM/ROM wrappers in some places, while the project has moved to `tc_sram`-based memories. For FPGA builds, the goal is to use Xilinx parameterized memory macros instead of separately synthesized Xilinx block memory IPs. That means the memory instantiation strategy needs to be updated so the FPGA path can map cleanly to the new `tc_sram` infrastructure.

### 2) Where the problem occurs
The relevant code is mainly in:

- `rtl/pulp_soc/l2_ram_multi_bank.sv`
  - This file directly instantiates `tc_sram` for the non-FPGA path and `fpga_interleaved_ram` for the FPGA emulation path.
  - The current structure is already split by `PULP_FPGA_EMUL`, so this is the main place where the SRAM implementation choice matters.

- `rtl/pulp_soc/boot_rom.sv`
  - This file similarly uses a generic ROM for non-FPGA and `fpga_bootrom` for FPGA emulation.
  - If the project is migrating away from generic memories, this is also a likely place, but the issue statement specifically mentions SRAMs, so it may not need changes unless the ROM path is also part of the migration.

- Memory-related file lists:
  - `rtl/components/src_files.yml`
  - `rtl/pulp_soc/src_files.yml`
  - top-level `src_files.yml`
  - `Bender.yml`
  
  These may need updates only if the new `tc_sram` modules are introduced as new source dependencies. However, from the provided context, `tc_sram` already appears to be available as a dependency through `tech_cells_generic`/related infrastructure, so source list changes may not be necessary.

### 3) Best practices to take into account
- Keep the change minimal and localized.
- Preserve existing behavior for non-FPGA and FPGA build targets.
- Do not alter address mapping or bus handshake logic unless required.
- Ensure the memory address slicing remains correct for banked/interleaved memory.
- Prefer using the technology-specific memory macro interface directly rather than synthesizing separate block RAM IP where the project already supports parametrized macros.
- Avoid broad refactors of file lists or dependencies unless compilation actually requires them.

### 4) How to fix the problem
The fix should update the SRAM instantiation path in `l2_ram_multi_bank.sv` so that the FPGA build can use the new `tc_sram`-compatible implementation or the appropriate FPGA macro interface, rather than relying on a separately generated generic RAM model/IP.

Given the provided code, the most relevant minimal change is to ensure the interleaved memory path uses the new `tc_sram` modules consistently and avoid retaining the older generic/SRAM split if it prevents using the desired FPGA parametrized macro flow.

In practice, based on the snippet, the code already instantiates `tc_sram` on the non-`PULP_FPGA_EMUL` branch, so the likely necessary change is around the conditional selection and/or the FPGA-side memory instantiation. Since the issue explicitly says “replace generic srams with new tc_sram modules,” the probable fix is to remove the older generic path where applicable and use `tc_sram` uniformly for the SRAM banks, while keeping only the FPGA-specific emulation model if that is strictly needed.

However, with only the provided context, the safest concrete patch is to update the source metadata or memory instantiation only where the generic memory is still used. The only direct generic memory instantiation shown is the boot ROM’s `generic_rom`, but that is ROM, not SRAM. The SRAM bank file already uses `tc_sram`.

Therefore, the issue as presented appears to already be partially addressed in the code snippet, and the remaining actionable fix from the provided locations is to ensure the source list includes the technology cell memory modules if they are not already brought in transitively. But since no direct missing `tc_sram` dependency is shown in the snippets, I cannot justify a source-file patch from the supplied evidence alone.

## Phase 2: FIX IMPLEMENTATION

I don’t have enough evidence in the provided snippets to produce a safe, minimal patch without risking an incorrect change. The main SRAM wrapper shown already uses `tc_sram`, so the actual buggy location is not fully established from the supplied code.

If you can provide the current branch’s exact `l2_ram_multi_bank.sv`/memory wrapper implementation or the failing build error, I can produce a precise patch in the required format.
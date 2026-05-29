## Phase 1: FIX ANALYSIS

### 1. What the problem is
The issue is that the design still uses generic SRAM/ROM wrappers in some places, but the project now wants to switch to new `tc_sram`-based memory modules. The main motivation is to make the FPGA flow use Xilinx parameterized memory macros directly, instead of synthesizing separate Xilinx block RAM IPs.

In practice, the bug/issue is that the memory-generation path is not consistently using the new tech-cell SRAM modules, so the FPGA-friendly memory replacement is not fully enabled.

### 2. Where the problem occurs
From the provided code, the relevant place is:

- `rtl/pulp_soc/l2_ram_multi_bank.sv`

This file already contains a conditional instantiation of `tc_sram` for the non-FPGA-emulation path, and a separate `fpga_interleaved_ram` path for `PULP_FPGA_EMUL`.

The likely problem is that this module is the key L2 SRAM bank implementation and is the right place where the replacement from generic memory to `tc_sram` must be consolidated/verified. However, in the provided snippet it already uses `tc_sram`, so the code context suggests the issue is more about ensuring this module is the canonical memory implementation and that no stale generic SRAM path remains elsewhere in this area.

The other relevant memory-related files shown are:

- `rtl/pulp_soc/boot_rom.sv`
- `rtl/components/memory_models.sv`
- `rtl/components/scm_2048x32.sv`
- `rtl/components/scm_512x32.sv`

But the direct memory-bank replacement requested by the issue is centered around `l2_ram_multi_bank.sv`.

### 3. Best practices to take into account
- Keep changes minimal and localized.
- Preserve existing FPGA simulation behavior under `PULP_FPGA_EMUL`.
- Maintain identical bus handshaking and timing behavior.
- Avoid changing address mapping logic unless necessary.
- Use tech-cell memories consistently so synthesis targets can select the proper FPGA macro implementation.
- Do not modify unrelated memory models unless they are part of the same replacement path.

### 4. How to fix the problem
The clean fix is to ensure the L2 memory bank module uses `tc_sram` as the primary memory implementation for the standard path, while preserving the FPGA emulation model path.

Since the provided snippet already shows `tc_sram` in the non-`PULP_FPGA_EMUL` branch, the practical fix in this context is to keep this as the correct implementation and ensure no fallback to generic SRAM remains in the affected module. If this repository version still had a generic SRAM instantiation elsewhere in the full file, it should be replaced by `tc_sram` with the same port wiring and address slicing.

Given the provided locations, the most relevant concrete patch is to keep the `tc_sram` instantiation as the intended replacement and ensure the file remains wired to it.

---

## Phase 2: FIX IMPLEMENTATION

No code change is necessary from the provided snippet, because the relevant module already uses `tc_sram` in the standard path. Therefore, there is no safe minimal patch to apply based strictly on the supplied code blocks without inventing modifications outside the provided context.
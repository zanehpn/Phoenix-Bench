### Phase 1: FIX ANALYSIS

1. **Problem summary**

`tb_axi_lite_regs` has a race between:
- the deterministic “known register” write/read check, and
- the background random `reg_load` activity (`toggle_load` tasks).

With some seeds, random direct loads update the register before the deterministic read assertion, so read data is no longer `64'hDEADBEEFDEADBEEF`, causing the failure.

2. **Where it occurs**

In `test/tb_axi_lite_regs.sv`:
- `proc_generate_axi_traffic` performs deterministic write/read and asserts fixed expected data.
- `proc_generate_direct_load` starts `toggle_load()` for every byte immediately after reset, i.e. concurrently and too early.
- `toggle_load` can trigger almost immediately (`$urandom_range(0, 20)`), causing collisions.

3. **Best practices for fix**

- Keep deterministic checks isolated from randomized background stimulus.
- Synchronize start of random traffic to happen *after* deterministic sanity checks.
- Make minimal changes to preserve existing random stress behavior for the rest of the test.

4. **Fix approach**

- Start `toggle_load` worker tasks **after** the known-register write/read assertions complete, inside `proc_generate_axi_traffic`, just before `lite_axi_master.run(...)`.
- Disable the separate early-start `proc_generate_direct_load` block to avoid duplicate/random early loaders.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>test/tb_axi_lite_regs.sv</file>
<original>    // Let random stimuli application checking is separate.
    lite_axi_master.run(NoReads, NoWrites);
    end_of_sim <= 1'b1;
  end</original>
<patched>    // Start random direct-load stimuli only after deterministic known-register checks.
    for (int unsigned i = 0; i < RegNumBytes; i++) begin
      automatic int unsigned j = i;
      fork
        toggle_load(j);
      join_none
    end

    // Let random stimuli application checking is separate.
    lite_axi_master.run(NoReads, NoWrites);
    end_of_sim <= 1'b1;
  end</patched>
```

# modification 2
```xml
<file>test/tb_axi_lite_regs.sv</file>
<original>  initial begin : proc_generate_direct_load
    for (int unsigned i = 0; i < RegNumBytes; i++) begin
      automatic int unsigned j = i;
      fork
        toggle_load(j);
      join_none
    end
  end</original>
<patched>  // Random direct-load generation is started from proc_generate_axi_traffic
  // after deterministic known-register checks to avoid seed-dependent collisions.
  initial begin : proc_generate_direct_load
  end</patched>
```
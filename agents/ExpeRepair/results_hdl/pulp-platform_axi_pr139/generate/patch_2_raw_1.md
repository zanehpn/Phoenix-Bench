### Phase 1: FIX ANALYSIS

1. **Problem summary**

`tb_axi_lite_regs` is flaky because the background `rand_load` activity can start too early and overwrite register bytes during the deterministic sanity sequence (`write` then immediate `read` of `0xDEADBEEFDEADBEEF`).

That explains failures like:
- expected: `DEADBEEFDEADBEEF`
- got: `DE01BEEF` (a byte got modified by random direct load)

2. **Where it happens**

In `test/tb_axi_lite_regs.sv`:
- `proc_generate_axi_traffic` performs a deterministic write/read check.
- `proc_generate_direct_load` starts `toggle_load()` tasks immediately after reset (independent initial block), so random direct loads may collide with that deterministic check.

3. **Best practices for fix**

- Keep deterministic checks isolated from random/background traffic.
- Avoid seed-dependent timing races between independent `initial` blocks.
- Make minimal changes to testbench scheduling (no protocol/functional behavior changes needed).

4. **Fix approach**

Start `toggle_load` threads **after** the deterministic known-register write/read assertions complete, and before random AXI traffic (`lite_axi_master.run(...)`) begins.  
This removes the collision window while preserving random-load behavior for the main randomized phase.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>test/tb_axi_lite_regs.sv</file>
<original>    // Let random stimuli application checking is separate.
    lite_axi_master.run(NoReads, NoWrites);
    end_of_sim <= 1'b1;
  end

  initial begin : proc_generate_direct_load
    for (int unsigned i = 0; i < RegNumBytes; i++) begin
      automatic int unsigned j = i;
      fork
        toggle_load(j);
      join_none
    end
  end</original>
<patched>    // Start random direct loads only after deterministic known-register checks.
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
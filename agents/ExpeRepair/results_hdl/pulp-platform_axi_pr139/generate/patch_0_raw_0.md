### Phase 1: FIX ANALYSIS

1. **Problem summary**

`tb_axi_lite_regs` has two concurrent stimulus sources:
- deterministic AXI write/read sanity check (`proc_generate_axi_traffic`)
- randomized direct register load toggling (`proc_generate_direct_load` via `toggle_load`)

In some seeds, random `reg_load` activity starts early and overwrites register bytes before/around the deterministic readback. That causes nondeterministic mismatch like:
- expected: `64'hDEADBEEFDEADBEEF`
- got: value with random-byte corruption (example log shows `de01beef` fragment)

2. **Where it occurs**

In `test/tb_axi_lite_regs.sv`:
- `proc_generate_direct_load` spawns `toggle_load` immediately.
- `toggle_load` begins random load loop right after reset.
- deterministic check in `proc_generate_axi_traffic` assumes register content remains what was written, but can be clobbered by random loads.

3. **Best practices for fix**

- Keep deterministic sanity checks isolated from random/background traffic.
- Avoid timing/seed-dependent races between independent test processes.
- Use explicit synchronization instead of relying on random wait ranges.

4. **Fix approach**

Introduce an explicit synchronization event:
- Declare a module-scope event (`start_rand_load`).
- Trigger it in `proc_generate_axi_traffic` **after** deterministic write/read assertions pass.
- Make each `toggle_load` task wait for this event before entering its forever random loop.

This is minimal, robust, and preserves existing random test behavior after the deterministic phase.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>test/tb_axi_lite_regs.sv</file>
<original>      assert (resp == axi_pkg::RESP_OKAY) else
          $fatal(1, "Access should be granted.");
      assert (data == axi_data_t'(64'hDEADBEEFDEADBEEF)) else
          $fatal(1, "Data is unexpected, should be axi_data_t'(64'hDEADBEEFDEADBEEF).");
    end

    // Let random stimuli application checking is separate.
    lite_axi_master.run(NoReads, NoWrites);
    end_of_sim <= 1'b1;</original>
<patched>      assert (resp == axi_pkg::RESP_OKAY) else
          $fatal(1, "Access should be granted.");
      assert (data == axi_data_t'(64'hDEADBEEFDEADBEEF)) else
          $fatal(1, "Data is unexpected, should be axi_data_t'(64'hDEADBEEFDEADBEEF).");
    end

    // Start random direct-load traffic only after deterministic access checks.
    -> start_rand_load;
    // Let random stimuli application checking is separate.
    lite_axi_master.run(NoReads, NoWrites);
    end_of_sim <= 1'b1;</patched>
```

# modification 2
```xml
<file>test/tb_axi_lite_regs.sv</file>
<original>  end

  initial begin : proc_generate_direct_load
    for (int unsigned i = 0; i &lt; RegNumBytes; i++) begin
      automatic int unsigned j = i;
      fork
        toggle_load(j);
      join_none
    end
  end</original>
<patched>  end

  event start_rand_load;

  initial begin : proc_generate_direct_load
    for (int unsigned i = 0; i &lt; RegNumBytes; i++) begin
      automatic int unsigned j = i;
      fork
        toggle_load(j);
      join_none
    end
  end</patched>
```

# modification 3
```xml
<file>test/tb_axi_lite_regs.sv</file>
<original>  task automatic toggle_load(int unsigned byte_i);
    byte_t       rand_val;
    int unsigned rand_wait;
    @(posedge rst_n);
    reg_load[byte_i] = 1'b0;
    reg_d[byte_i]    = 8'h00;
    @(posedge clk);
    forever begin
      rand_wait = $urandom_range(0, 20);
      repeat (rand_wait) @(posedge clk);
      rand_val          = byte_t'($urandom());
      reg_d[byte_i]    &lt;= #ApplTime rand_val;
      reg_load[byte_i] &lt;= #ApplTime 1'b1;
      @(posedge clk);
      reg_d[byte_i]    &lt;= #ApplTime '0;
      reg_load[byte_i] &lt;= #ApplTime 1'b0;
    end
  endtask : toggle_load</original>
<patched>  task automatic toggle_load(int unsigned byte_i);
    byte_t       rand_val;
    int unsigned rand_wait;
    @(posedge rst_n);
    reg_load[byte_i] = 1'b0;
    reg_d[byte_i]    = 8'h00;
    @(posedge clk);
    @(start_rand_load);
    forever begin
      rand_wait = $urandom_range(0, 20);
      repeat (rand_wait) @(posedge clk);
      rand_val          = byte_t'($urandom());
      reg_d[byte_i]    &lt;= #ApplTime rand_val;
      reg_load[byte_i] &lt;= #ApplTime 1'b1;
      @(posedge clk);
      reg_d[byte_i]    &lt;= #ApplTime '0;
      reg_load[byte_i] &lt;= #ApplTime 1'b0;
    end
  endtask : toggle_load</patched>
```
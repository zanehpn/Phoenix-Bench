### Phase 1: FIX ANALYSIS

1. **Problem summary**

The failure is caused by a **race between deterministic sanity checks and randomized direct register loads** in `tb_axi_lite_regs.sv`.

- The test writes `DEADBEEFDEADBEEF` to address `0x0`, then immediately reads it back and expects the same value.
- In parallel, `proc_generate_direct_load` starts right after reset and can randomly assert `reg_load[...]`, which overwrites register bytes.
- Depending on seed/timing, a random load can occur between the write and read, producing mismatched readback data and assertion failure.

2. **Where it occurs**

In `test/tb_axi_lite_regs.sv`:

- `proc_generate_axi_traffic` performs the deterministic write/read check.
- `proc_generate_direct_load` independently launches `toggle_load()` threads immediately after reset.
- No synchronization exists between these two flows.

3. **Best practices for the fix**

- Keep deterministic checks isolated from random background stimulus.
- Remove seed-dependent races by adding explicit synchronization.
- Prefer minimal behavioral changes: start random direct loads only after the deterministic sanity check is complete.

4. **Fix approach**

Add a module-scope event (`start_rand_load`) and:
- Trigger it in `proc_generate_axi_traffic` right after the known write/read assertions pass.
- Make `proc_generate_direct_load` wait for that event before spawning random `toggle_load()` processes.

This preserves all random-load behavior during randomized traffic phase while ensuring deterministic sanity check is stable.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>test/tb_axi_lite_regs.sv</file>
<original>  // -------------------------------
  // AXI Rand Masters and Slaves
  // -------------------------------
  // Masters control simulation run time
  initial begin : proc_generate_axi_traffic
    automatic rand_lite_master_t lite_axi_master = new ( master_dv, "Lite Master");
    automatic axi_data_t      data = '0;
    automatic axi_pkg::resp_t resp = '0;
    end_of_sim <= 1'b0;
    lite_axi_master.reset();
    @(posedge rst_n);
    repeat (5) @(posedge clk);
    // Test known register.
    // Write to it.
    lite_axi_master.write(axi_addr_t'(32'h0000_0000), axi_pkg::prot_t'('0),
        axi_data_t'(64'hDEADBEEFDEADBEEF), axi_strb_t'(8'hFF), resp);
    if (PrivProtOnly || SecuProtOnly) begin
      assert (resp == axi_pkg::RESP_SLVERR) else
          $fatal(1, "PrivProtOnly || SecuProtOnly: Unprivileged access was falsely granted.");
    end else begin
      assert (resp == axi_pkg::RESP_OKAY) else
          $fatal(1, "Access should be granted");
    end
    // Read from it.
    lite_axi_master.read(axi_addr_t'(32'h0000_0000), axi_pkg::prot_t'('0), data, resp);
    if (PrivProtOnly || SecuProtOnly) begin
      // Expect error response
      assert (resp == axi_pkg::RESP_SLVERR) else
          $fatal(1, "PrivProtOnly || SecuProtOnly: Unprivileged access was falsely granted.");
      assert (data == axi_data_t'(32'hBA5E1E55)) else
          $fatal(1, "Data is unexpected, should be axi_data_t'(32'hBA5E1E55).");
    end else begin
      assert (resp == axi_pkg::RESP_OKAY) else
          $fatal(1, "Access should be granted.");
      assert (data == axi_data_t'(64'hDEADBEEFDEADBEEF)) else
          $fatal(1, "Data is unexpected, should be axi_data_t'(64'hDEADBEEFDEADBEEF).");
    end

    // Let random stimuli application checking is separate.
    lite_axi_master.run(NoReads, NoWrites);
    end_of_sim <= 1'b1;
  end</original>
<patched>  // -------------------------------
  // AXI Rand Masters and Slaves
  // -------------------------------
  event start_rand_load;
  // Masters control simulation run time
  initial begin : proc_generate_axi_traffic
    automatic rand_lite_master_t lite_axi_master = new ( master_dv, "Lite Master");
    automatic axi_data_t      data = '0;
    automatic axi_pkg::resp_t resp = '0;
    end_of_sim <= 1'b0;
    lite_axi_master.reset();
    @(posedge rst_n);
    repeat (5) @(posedge clk);
    // Test known register.
    // Write to it.
    lite_axi_master.write(axi_addr_t'(32'h0000_0000), axi_pkg::prot_t'('0),
        axi_data_t'(64'hDEADBEEFDEADBEEF), axi_strb_t'(8'hFF), resp);
    if (PrivProtOnly || SecuProtOnly) begin
      assert (resp == axi_pkg::RESP_SLVERR) else
          $fatal(1, "PrivProtOnly || SecuProtOnly: Unprivileged access was falsely granted.");
    end else begin
      assert (resp == axi_pkg::RESP_OKAY) else
          $fatal(1, "Access should be granted");
    end
    // Read from it.
    lite_axi_master.read(axi_addr_t'(32'h0000_0000), axi_pkg::prot_t'('0), data, resp);
    if (PrivProtOnly || SecuProtOnly) begin
      // Expect error response
      assert (resp == axi_pkg::RESP_SLVERR) else
          $fatal(1, "PrivProtOnly || SecuProtOnly: Unprivileged access was falsely granted.");
      assert (data == axi_data_t'(32'hBA5E1E55)) else
          $fatal(1, "Data is unexpected, should be axi_data_t'(32'hBA5E1E55).");
    end else begin
      assert (resp == axi_pkg::RESP_OKAY) else
          $fatal(1, "Access should be granted.");
      assert (data == axi_data_t'(64'hDEADBEEFDEADBEEF)) else
          $fatal(1, "Data is unexpected, should be axi_data_t'(64'hDEADBEEFDEADBEEF).");
    end

    // Start random direct loads only after deterministic sanity checks.
    ->start_rand_load;

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
<patched>  initial begin : proc_generate_direct_load
    @start_rand_load;
    for (int unsigned i = 0; i < RegNumBytes; i++) begin
      automatic int unsigned j = i;
      fork
        toggle_load(j);
      join_none
    end
  end</patched>
```
### Phase 1: FIX ANALYSIS

1. **Problem summary**

`tb_axi_lite_regs` has a nondeterministic failure: the “known register” readback check sometimes gets corrupted data (`de01beef` instead of `deadbeefdeadbeef`) for specific seeds.

This happens because randomized direct-load traffic (`toggle_load`) can update register bytes **while** the deterministic write/read sanity check is running.

2. **Where it occurs**

In `test/tb_axi_lite_regs.sv`:

- `proc_generate_axi_traffic` performs a deterministic write/read sequence first.
- `proc_generate_direct_load` starts `toggle_load` workers immediately after reset.
- `toggle_load` continuously asserts `reg_load` with random byte values.

So there is a race/collision between the deterministic check and random load injection.

3. **Best practices for fix**

- Keep deterministic sanity checks isolated from random background stimulus.
- Gate background random generators until directed checks complete.
- Make minimal changes to preserve existing random testing behavior afterward.

4. **Fix approach**

Introduce a small synchronization flag:
- Initialize it to `0`.
- Set it to `1` only after the deterministic write/read check is done.
- In `toggle_load`, wait for this flag before entering the random load loop.

This removes seed-dependent collisions during the known-value check, while preserving random load behavior for the rest of simulation.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>test/tb_axi_lite_regs.sv</file>
<original>  ) master ();
  AXI_LITE_DV #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth      ),
    .AXI_DATA_WIDTH ( AxiDataWidth      )
  ) master_dv (clk);
  `AXI_LITE_ASSIGN(master, master_dv)

  // -------------------------------
  // AXI Rand Masters and Slaves
  // -------------------------------
  // Masters control simulation run time
  initial begin : proc_generate_axi_traffic
    automatic rand_lite_master_t lite_axi_master = new ( master_dv, "Lite Master");
    automatic axi_data_t      data = '0;
    automatic axi_pkg::resp_t resp = '0;
    end_of_sim &lt;= 1'b0;
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
    end_of_sim &lt;= 1'b1;
  end</original>
<patched>  ) master ();
  AXI_LITE_DV #(
    .AXI_ADDR_WIDTH ( AxiAddrWidth      ),
    .AXI_DATA_WIDTH ( AxiDataWidth      )
  ) master_dv (clk);
  `AXI_LITE_ASSIGN(master, master_dv)

  logic rand_load_enable;

  // -------------------------------
  // AXI Rand Masters and Slaves
  // -------------------------------
  // Masters control simulation run time
  initial begin : proc_generate_axi_traffic
    automatic rand_lite_master_t lite_axi_master = new ( master_dv, "Lite Master");
    automatic axi_data_t      data = '0;
    automatic axi_pkg::resp_t resp = '0;
    end_of_sim        &lt;= 1'b0;
    rand_load_enable  &lt;= 1'b0;
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

    // Enable randomized direct loads only after deterministic sanity checks complete.
    rand_load_enable &lt;= 1'b1;

    // Let random stimuli application checking is separate.
    lite_axi_master.run(NoReads, NoWrites);
    end_of_sim &lt;= 1'b1;
  end</patched>
```

# modification 2
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

    // Avoid clobbering deterministic register read/write checks.
    wait (rand_load_enable);

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
  endtask : toggle_load</patched>
```
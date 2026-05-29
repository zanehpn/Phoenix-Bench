### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue requests a new handshake primitive for joining streams that supports:

- **dynamic input selection** (join only a masked subset per transaction),
- **independent input handshakes** (inputs can be consumed over multiple cycles, not necessarily all in the same cycle).

Current `stream_join` behavior in common_cells is the strict “simultaneous join” model, so it cannot satisfy this use case.

---

2. **Where the problem occurs**

- Functionally, the repository currently has `stream_join` but no dynamic/independent counterpart.
- From provided context:
  - `src/stream_fork.sv` shows the “specular” pattern and state-based handshake tracking logic.
  - `Bender.yml` does not list a `stream_join_dynamic` source.
  - `README.md` does not document such an IP.

So the fix should add a new IP module (separate from existing `stream_join`) and register/document it.

---

3. **Best practices for the fix**

- Keep **backward compatibility**: do not change existing `stream_join` interface/semantics.
- Add a **new module** (`stream_join_dynamic`) instead.
- Use clean ready/valid semantics:
  - consume each selected input exactly once per output transaction,
  - latch selection during an in-flight transaction,
  - block already-consumed inputs until output handshake completes.
- Keep reset/parameter assertions consistent with common_cells style.
- Register the new source in build metadata and documentation.

---

4. **How to fix**

- Add `src/stream_join_dynamic.sv` implementing:
  - `sel_i` mask for dynamic subset,
  - per-input consumption tracking (`pending_q`),
  - latched selection (`sel_q`) while transaction is in-flight,
  - output `valid_o` asserted once all selected inputs are consumed,
  - independent `ready_o[i]` for not-yet-consumed selected inputs.
- Add the file to `Bender.yml`.
- Add module description entry in `README.md`.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>Bender.yml</file>
<original>  - src/stream_delay.sv
  - src/stream_fifo.sv
  - src/stream_fork_dynamic.sv
  - src/clk_mux_glitch_free.sv</original>
<patched>  - src/stream_delay.sv
  - src/stream_fifo.sv
  - src/stream_fork_dynamic.sv
  - src/stream_join_dynamic.sv
  - src/clk_mux_glitch_free.sv</patched>
```

# modification 2
```xml
<file>README.md</file>
<original>| `stream_join`              | Ready/valid handshake join multiple to one common                                                         | active       |               |
| `stream_mux`               | Ready/valid interface multiplexer                                                                         | active       |               |</original>
<patched>| `stream_join`              | Ready/valid handshake join multiple to one common                                                         | active       |               |
| `stream_join_dynamic`      | Ready/valid handshake join with dynamic selection and independent per-input handshakes                   | active       |               |
| `stream_mux`               | Ready/valid interface multiplexer                                                                         | active       |               |</patched>
```

# modification 3
```xml
<file>src/stream_join_dynamic.sv</file>
<original></original>
<patched>// Copyright 2024 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License. You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Stream join dynamic: Joins a dynamically selected subset of `N_INP` input stream handshakes
// into one output stream handshake.
// For each output handshake, every selected input stream handshakes exactly once. Input streams
// are granted independently and do not need to handshake simultaneously.
//
// This module has no data ports because stream data does not need to be joined internally: data
// can be handled externally while this module provides the synchronization handshakes.

module stream_join_dynamic #(
    parameter int unsigned N_INP = 0  // Synopsys DC requires a default value for parameters.
) (
    input  logic                clk_i,
    input  logic                rst_ni,
    input  logic [N_INP-1:0]    valid_i,
    output logic [N_INP-1:0]    ready_o,
    input  logic [N_INP-1:0]    sel_i,
    output logic                valid_o,
    input  logic                ready_i
);

    logic [N_INP-1:0] sel_q, sel_d;
    logic [N_INP-1:0] pending_q, pending_d;
    logic             active_q, active_d;

    logic [N_INP-1:0] sel_eff;
    logic [N_INP-1:0] handshakes;
    logic [N_INP-1:0] pending_n;
    logic             any_sel;
    logic             all_done;
    logic             out_handshake;

    always_comb begin
        // Defaults
        sel_d         = sel_q;
        pending_d     = pending_q;
        active_d      = active_q;
        ready_o       = '0;
        valid_o       = 1'b0;

        // Selection is dynamic while idle, and latched while active.
        sel_eff       = active_q ? sel_q : sel_i;

        // Inputs that are selected and not consumed yet can handshake.
        ready_o       = sel_eff & ~pending_q;
        handshakes    = valid_i & ready_o;
        pending_n     = pending_q | handshakes;

        any_sel       = |sel_eff;
        all_done      = any_sel && (pending_n == sel_eff);
        valid_o       = all_done;
        out_handshake = valid_o && ready_i;

        if (out_handshake) begin
            // Transaction complete.
            sel_d     = '0;
            pending_d = '0;
            active_d  = 1'b0;
        end else if (all_done || (|pending_n)) begin
            // Transaction in progress / waiting for output handshake.
            sel_d     = sel_eff;
            pending_d = pending_n;
            active_d  = 1'b1;
        end else begin
            // Idle.
            sel_d     = '0;
            pending_d = '0;
            active_d  = 1'b0;
        end
    end

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            sel_q     <= '0;
            pending_q <= '0;
            active_q  <= 1'b0;
        end else begin
            sel_q     <= sel_d;
            pending_q <= pending_d;
            active_q  <= active_d;
        end
    end

// pragma translate_off
`ifndef VERILATOR
    initial begin: p_assertions
        assert (N_INP >= 1) else $fatal(1, "Number of inputs must be at least 1!");
    end
`endif
// pragma translate_on

endmodule
</patched>
```
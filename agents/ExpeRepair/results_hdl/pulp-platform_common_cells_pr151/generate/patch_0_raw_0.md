### Phase 1: FIX ANALYSIS

1. **Problem statement**

The current `stream_join` behavior is an “all-at-once” join:
- it always joins **all** inputs, and
- it only handshakes when all inputs are valid in the same transaction window.

The issue requests a variant that:
- supports a **dynamic input selection mask** (join only a subset),
- allows **independent input handshakes** (inputs may arrive/handshake in different cycles).

2. **Where this occurs**

- The existing infrastructure already has a dynamic counterpart for forking (`stream_fork_dynamic`), but no equivalent for joining.
- Based on provided context, this is mainly a **missing IP/module feature**, not a small bug in existing logic.
- Integration points are:
  - `Bender.yml` source list (to compile/export the new IP),
  - `README.md` cell list (to document the new IP).

3. **Best practices for fix**

- Keep backward compatibility: do **not** change `stream_join` semantics.
- Add a new IP (`stream_join_dynamic`) rather than modifying existing `stream_join`.
- Use clear ready/valid state handling:
  - track which selected inputs are still pending,
  - accept selected inputs independently (`ready_o[i]` high while pending),
  - raise `valid_o` once all selected inputs have been consumed,
  - wait for output handshake (`ready_i`) before starting next join round.
- Include parameter sanity check (`N_INP >= 1`).

4. **Fix approach**

- Add new module `src/stream_join_dynamic.sv` implementing dynamic selection + independent handshakes.
- Add this file to `Bender.yml` sources.
- Document it in `README.md` table.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>Bender.yml</file>
<original>  - src/stream_intf.sv
  - src/stream_join.sv
  - src/stream_mux.sv</original>
<patched>  - src/stream_intf.sv
  - src/stream_join.sv
  - src/stream_join_dynamic.sv
  - src/stream_mux.sv</patched>
```

# modification 2
```xml
<file>README.md</file>
<original>| `stream_join`              | Ready/valid handshake join multiple to one common                                                         | active       |               |
| `stream_mux`               | Ready/valid interface multiplexer                                                                         | active       |               |
| `stream_register`          | Register with ready/valid interface                                                                       | active       |               |
| `stream_fork`              | Ready/valid fork                                                                                          | active       |               |
| `stream_fork_dynamic`      | Ready/valid fork, with selection mask for partial forking                                                 | active       |               |</original>
<patched>| `stream_join`              | Ready/valid handshake join multiple to one common                                                         | active       |               |
| `stream_join_dynamic`      | Ready/valid join, with selection mask for partial joining and independent input handshakes               | active       |               |
| `stream_mux`               | Ready/valid interface multiplexer                                                                         | active       |               |
| `stream_register`          | Register with ready/valid interface                                                                       | active       |               |
| `stream_fork`              | Ready/valid fork                                                                                          | active       |               |
| `stream_fork_dynamic`      | Ready/valid fork, with selection mask for partial forking                                                 | active       |               |</patched>
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

// Stream join dynamic: Joins a *selected subset* of N_INP input stream handshakes to one output
// stream handshake. For each output handshake, every selected input stream handshakes exactly once.
// Selected inputs can handshake independently (not necessarily in the same cycle).
//
// This module has no data ports because stream data can be handled externally.

module stream_join_dynamic #(
    parameter int unsigned N_INP = 0
) (
    input  logic             clk_i,
    input  logic             rst_ni,
    input  logic [N_INP-1:0] sel_i,
    input  logic [N_INP-1:0] valid_i,
    output logic [N_INP-1:0] ready_o,
    output logic             valid_o,
    input  logic             ready_i
);

  typedef enum logic {COLLECT, WAIT_OUT} state_t;

  state_t inp_state_d, inp_state_q;

  logic [N_INP-1:0] pending_d, pending_q;
  logic [N_INP-1:0] active_pending;
  logic [N_INP-1:0] all_zeros;

  always_comb begin
    inp_state_d     = inp_state_q;
    pending_d       = pending_q;
    ready_o         = '0;
    valid_o         = 1'b0;
    active_pending  = pending_q;

    unique case (inp_state_q)
      COLLECT: begin
        // Start a new collection round when no inputs are pending.
        if (pending_q == all_zeros) begin
          active_pending = sel_i;
        end

        // Allow all currently pending inputs to handshake independently.
        ready_o = active_pending;

        if (active_pending != all_zeros) begin
          pending_d = active_pending & ~valid_i;
          if ((active_pending & ~valid_i) == all_zeros) begin
            inp_state_d = WAIT_OUT;
          end
        end else begin
          pending_d = all_zeros;
        end
      end

      WAIT_OUT: begin
        valid_o = 1'b1;
        if (ready_i) begin
          pending_d   = all_zeros;
          inp_state_d = COLLECT;
        end
      end

      default: begin
        inp_state_d = COLLECT;
        pending_d   = all_zeros;
      end
    endcase
  end

  always_ff @(posedge clk_i, negedge rst_ni) begin
    if (!rst_ni) begin
      inp_state_q <= COLLECT;
      pending_q   <= '0;
    end else begin
      inp_state_q <= inp_state_d;
      pending_q   <= pending_d;
    end
  end

  assign all_zeros = '0;

// pragma translate_off
`ifndef VERILATOR
  initial begin : p_assertions
    assert (N_INP >= 1) else $fatal(1, "Number of inputs must be at least 1!");
  end
`endif
// pragma translate_on

endmodule</patched>
```
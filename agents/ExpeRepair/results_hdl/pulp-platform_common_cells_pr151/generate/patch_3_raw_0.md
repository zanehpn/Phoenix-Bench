### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue requests a join primitive with two capabilities that current `stream_join` does not provide:

- **Dynamic subset selection** of input streams to participate in a join transaction.
- **Independent input handshakes**, i.e., each selected input may complete at different cycles, and the output fires once all selected inputs have completed.

This is effectively the “specular” counterpart of dynamic forking behavior.

2. **Where this maps in the current code context**

- `src/stream_fork.sv` already contains sequential handshake-tracking logic for independent completion across multiple outputs (fork side).
- There is currently no corresponding dynamic+independent join implementation in the provided context.
- `README.md` lists available IPs and currently has no `stream_join_dynamic` entry.

3. **Best practices for the fix**

- Keep the existing `stream_fork` behavior unchanged.
- Add a **new IP module** rather than breaking compatibility of existing `stream_join`.
- Keep logic simple and robust:
  - Track per-input completion state (`done_q`).
  - Latch selection for the active transaction.
  - Assert output valid only once all selected inputs have completed.
  - Reset state cleanly on output handshake.
- Add basic parameter sanity assertion (`N_INP >= 1`).
- Update documentation table to expose the new IP.

4. **How to fix**

- Add a new module `stream_join_dynamic` (in `src/stream_fork.sv` in this patch) that:
  - accepts `valid_i[N]`, `sel_i[N]`, and produces `ready_o[N]`,
  - allows selected inputs to handshake independently over time,
  - raises `valid_o` when all selected inputs have handshaked,
  - completes the joined transaction on `valid_o && ready_i`.
- Update README “Data Path Elements” table to list `stream_join_dynamic`.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>src/stream_fork.sv</file>
<original>    assign all_ones = '1;   // Synthesis fix for Vivado, which does not correctly compute the width
                            // of the '1 literal when assigned to a port of parametrized width.


// pragma translate_off
`ifndef VERILATOR
    initial begin: p_assertions
        assert (N_OUP >= 1) else $fatal(1, "Number of outputs must be at least 1!");
    end
`endif
// pragma translate_on
</original>
<patched>    assign all_ones = '1;   // Synthesis fix for Vivado, which does not correctly compute the width
                            // of the '1 literal when assigned to a port of parametrized width.


// pragma translate_off
`ifndef VERILATOR
    initial begin: p_assertions
        assert (N_OUP >= 1) else $fatal(1, "Number of outputs must be at least 1!");
    end
`endif
// pragma translate_on

endmodule

// Stream join dynamic: Join a dynamically selected subset of input streams (ready-valid) into one
// output handshake. For each output stream handshake, every selected input stream handshakes exactly
// once. Selected inputs may handshake independently and do not have to handshake simultaneously.
//
module stream_join_dynamic #(
    parameter int unsigned N_INP = 0    // Synopsys DC requires a default value for parameters.
) (
    input  logic                clk_i,
    input  logic                rst_ni,
    input  logic [N_INP-1:0]    valid_i,
    output logic [N_INP-1:0]    ready_o,
    input  logic [N_INP-1:0]    sel_i,
    output logic                valid_o,
    input  logic                ready_i
);

    logic [N_INP-1:0] done_d, done_q;
    logic [N_INP-1:0] sel_d,  sel_q;
    logic             active_d, active_q;

    logic [N_INP-1:0] active_sel, capture;
    logic             all_done, started;

    always_comb begin
        done_d   = done_q;
        sel_d    = sel_q;
        active_d = active_q;
        ready_o  = '0;

        // Select mask may change only between transactions.
        if (!active_q) begin
            sel_d = sel_i;
        end

        active_sel = active_q ? sel_q : sel_i;

        // Accept selected inputs that have not handshaked yet.
        ready_o = active_sel & ~done_q;
        capture = ready_o & valid_i;
        done_d  = done_q | capture;

        // Start transaction on first captured input.
        if (!active_q && (|capture)) begin
            active_d = 1'b1;
        end

        started  = active_q | (|capture);
        all_done = &((~active_sel) | done_d);
        valid_o  = started & all_done;

        // Complete transaction on output handshake.
        if (valid_o && ready_i) begin
            done_d   = '0;
            active_d = 1'b0;
        end
    end

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            done_q   <= '0;
            sel_q    <= '0;
            active_q <= 1'b0;
        end else begin
            done_q   <= done_d;
            sel_q    <= sel_d;
            active_q <= active_d;
        end
    end

// pragma translate_off
`ifndef VERILATOR
    initial begin: p_assertions_stream_join_dynamic
        assert (N_INP >= 1) else $fatal(1, "Number of inputs must be at least 1!");
    end
`endif
// pragma translate_on

endmodule
</patched>
```

# modification 2
```xml
<file>README.md</file>
<original>| `stream_join`              | Ready/valid handshake join multiple to one common                                                         | active       |               |
| `stream_mux`               | Ready/valid interface multiplexer                                                                         | active       |               |
| `stream_register`          | Register with ready/valid interface                                                                       | active       |               |
| `stream_fork`              | Ready/valid fork                                                                                          | active       |               |
| `stream_fork_dynamic`      | Ready/valid fork, with selection mask for partial forking                                                 | active       |               |
| `stream_filter`            | Ready/valid filter                                                                                        | active       |               |</original>
<patched>| `stream_join`              | Ready/valid handshake join multiple to one common                                                         | active       |               |
| `stream_join_dynamic`      | Ready/valid join with dynamic selection mask and independent input handshakes                             | active       |               |
| `stream_mux`               | Ready/valid interface multiplexer                                                                         | active       |               |
| `stream_register`          | Register with ready/valid interface                                                                       | active       |               |
| `stream_fork`              | Ready/valid fork                                                                                          | active       |               |
| `stream_fork_dynamic`      | Ready/valid fork, with selection mask for partial forking                                                 | active       |               |
| `stream_filter`            | Ready/valid filter                                                                                        | active       |               |</patched>
```


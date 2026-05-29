### Phase 1: FIX ANALYSIS

1. **Problem summary**

The issue is a **feature gap** in stream joining:
- `stream_join` only supports joining **all** inputs.
- It requires all selected input handshakes to happen **simultaneously**.

Requested behavior:
- dynamically choose which inputs participate (mask/select),
- allow participating inputs to handshake **independently over multiple cycles**,
- only produce the joined output handshake once all selected inputs have handshaken once.

2. **Where this should be addressed**

From the provided context, there is no `stream_join_dynamic` implementation yet, while `stream_fork_dynamic` exists conceptually as the analogous feature on the fork side.  
So the fix is to provide a **new IP**: `stream_join_dynamic`.

Given available editable context, this is implemented by adding a new module definition in `src/stream_fork.sv` (same compilation unit), and documenting it in `README.md`.

3. **Best practices for the fix**

- Keep existing IP behavior unchanged (`stream_join`, `stream_fork` remain backward compatible).
- Add new functionality as a separate module (`stream_join_dynamic`) to avoid regressions.
- Latch/track selected participants per in-flight join transaction.
- Ensure exactly one handshake per selected input per transaction.
- Block further input handshakes once join is complete and waiting for downstream `ready_i`.
- Include parameter guard assertions (`N_INP >= 1`).

4. **How the fix works**

`stream_join_dynamic` adds:
- `sel_i`: dynamic mask of inputs participating in current join.
- Per-transaction state:
  - latched selection mask,
  - bitmap of already-handshaken selected inputs.
- `ready_o[k]` is asserted independently for each selected, not-yet-seen input.
- `valid_o` is asserted once all selected inputs are seen.
- When `valid_o && ready_i`, transaction completes and state clears for next dynamic selection.

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

// Stream join dynamic: Joins a dynamically selected subset of `N_INP` input stream handshakes into
// one output handshake. Each selected input handshakes exactly once per output handshake.
// Selected inputs can handshake independently (not necessarily simultaneously).
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

    logic [N_INP-1:0] sel_d, sel_q;
    logic [N_INP-1:0] seen_d, seen_q;
    logic             active_d, active_q;

    logic [N_INP-1:0] sel_cur, seen_cur;
    logic [N_INP-1:0] handshake_vec, seen_nxt;
    logic             done_cur, done_nxt;

    always_comb begin
        sel_cur = active_q ? sel_q  : sel_i;
        seen_cur = active_q ? seen_q : '0;

        done_cur = ((seen_cur & sel_cur) == sel_cur);

        ready_o = '0;
        if (!done_cur) begin
            ready_o = sel_cur & ~seen_cur;
        end

        handshake_vec = valid_i & ready_o;
        seen_nxt = seen_cur | handshake_vec;
        done_nxt = ((seen_nxt & sel_cur) == sel_cur);

        valid_o = done_nxt;

        if (done_nxt && ready_i) begin
            active_d = 1'b0;
            sel_d    = '0;
            seen_d   = '0;
        end else begin
            active_d = 1'b1;
            sel_d    = sel_cur;
            seen_d   = seen_nxt;
        end
    end

    always_ff @(posedge clk_i, negedge rst_ni) begin
        if (!rst_ni) begin
            active_q <= 1'b0;
            sel_q    <= '0;
            seen_q   <= '0;
        end else begin
            active_q <= active_d;
            sel_q    <= sel_d;
            seen_q   <= seen_d;
        end
    end

// pragma translate_off
`ifndef VERILATOR
    initial begin: p_assertions
        assert (N_INP >= 1) else $fatal(1, "Number of inputs must be at least 1!");
    end
`endif
// pragma translate_on
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
| `stream_filter`            | Ready/valid filter                                                                                        | active       |               |
| `stream_delay`             | Randomize or delay ready/valid interface                                                                  | active       |               |</original>
<patched>| `stream_join`              | Ready/valid handshake join multiple to one common                                                         | active       |               |
| `stream_join_dynamic`      | Ready/valid join with dynamic selection mask and independent input handshakes                             | active       |               |
| `stream_mux`               | Ready/valid interface multiplexer                                                                         | active       |               |
| `stream_register`          | Register with ready/valid interface                                                                       | active       |               |
| `stream_fork`              | Ready/valid fork                                                                                          | active       |               |
| `stream_fork_dynamic`      | Ready/valid fork, with selection mask for partial forking                                                 | active       |               |
| `stream_filter`            | Ready/valid filter                                                                                        | active       |               |
| `stream_delay`             | Randomize or delay ready/valid interface                                                                  | active       |               |</patched>
```


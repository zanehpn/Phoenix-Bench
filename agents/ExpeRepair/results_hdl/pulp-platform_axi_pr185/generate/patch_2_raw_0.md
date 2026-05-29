## Phase 1: FIX ANALYSIS

### 1) What the problem is
Mentor Precision infers latches in `axi_dw_upsizer` and `axi_dw_downsizer` because some automatic temporary variables (`r_data` / `w_data`) are initialized from a signal and then only conditionally overwritten in a loop.

In particular, these temporaries are used as “copy + selective overwrite” buffers, but some synthesis tools do not reliably treat the initialization as a default assignment. That makes them think the variable may retain its previous value, which is interpreted as latch behavior.

### 2) Where the problem occurs
The issue occurs in the following blocks:

- `src/axi_dw_upsizer.sv`
  - R-channel serialization:
    - `automatic slv_data_t r_data = slv_r_tran[t].data;`
  - W-channel serialization:
    - `automatic mst_data_t w_data = w_req_d.w.data;`

- `src/axi_dw_downsizer.sv`
  - R-channel serialization:
    - `automatic slv_data_t r_data = r_req_d.r.data;`
  - W-channel serialization:
    - `automatic mst_data_t w_data = mst_req.w.data;`

The provided issue notes indicate that the upsizer case is especially suspicious because the variable is meant to start at a known default (`'0` or the existing data value, depending on context) and then be overwritten lane-by-lane.

### 3) Best practices to take into account
- Avoid relying on automatic variable initialization as the sole “default” value when synthesis tools may misinterpret it.
- Prefer explicit combinational defaults before conditional updates.
- Do not introduce unnecessary structural changes if only a small coding pattern change is required.
- Keep the behavior identical for simulation and synthesis.
- Make the fix minimal and localized to the affected assignments.

### 4) How to fix the problem
The safest fix is to avoid the pattern that triggers latch inference by:
- removing the automatic variable initialization at declaration,
- explicitly assigning a default value immediately after declaration.

For the affected cases, an explicit assignment such as:
```systemverilog
automatic slv_data_t r_data;
r_data = '0;
```
or, where the design intends to preserve an existing value before selective overwrite:
```systemverilog
automatic mst_data_t w_data;
w_data = mst_req.w.data;
```
makes the intent unambiguous to synthesis tools.

Given the issue description, the minimal fix should target the code paths that are causing latch inference rather than rewriting all similar blocks.

---

## Phase 2: FIX IMPLEMENTATION

```text
<file>src/axi_dw_upsizer.sv</file>
<original>
              automatic slv_data_t r_data = slv_r_tran[t].data;

              // Valid output
              slv_r_valid_tran[t] = 1'b1                                       ;
              slv_r_tran[t].last  = mst_resp.r.last && (r_req_q.burst_len == 0);

              // Lane steering
              for (int b = 0; b < AxiMstPortStrbWidth; b++) begin
                if ((b >= mst_port_offset) &&
                    (b - mst_port_offset < (1 << r_req_q.orig_ar_size)) &&
                    (b + slv_port_offset - mst_port_offset < AxiSlvPortStrbWidth)) begin
                  r_data[b + slv_port_offset - mst_port_offset] = mst_resp.r.data[8*b +: 8];
                end
              end
              slv_r_tran[t].data = r_data;
</original>
<patched>
              automatic slv_data_t r_data;
              r_data = '0;

              // Valid output
              slv_r_valid_tran[t] = 1'b1                                       ;
              slv_r_tran[t].last  = mst_resp.r.last && (r_req_q.burst_len == 0);

              // Lane steering
              for (int b = 0; b < AxiMstPortStrbWidth; b++) begin
                if ((b >= mst_port_offset) &&
                    (b - mst_port_offset < (1 << r_req_q.orig_ar_size)) &&
                    (b + slv_port_offset - mst_port_offset < AxiSlvPortStrbWidth)) begin
                  r_data[b + slv_port_offset - mst_port_offset] = mst_resp.r.data[8*b +: 8];
                end
              end
              slv_r_tran[t].data = r_data;
</patched>
```

```text
<file>src/axi_dw_upsizer.sv</file>
<original>
            automatic mst_data_t w_data = w_req_d.w.data;

            // Serialization
            for (int b = 0; b < AxiMstPortStrbWidth; b++)
              if ((b >= mst_port_offset) &&
                  (b - mst_port_offset < (1 << w_req_q.orig_aw_size)) &&
                  (b + slv_port_offset - mst_port_offset < AxiSlvPortStrbWidth)) begin
                w_data[b]         = slv_req_i.w.data[8*(b + slv_port_offset - mst_port_offset) +: 8];
                w_req_d.w.strb[b] = slv_req_i.w.strb[b + slv_port_offset - mst_port_offset]         ;
              end
</original>
<patched>
            automatic mst_data_t w_data;
            w_data = w_req_d.w.data;

            // Serialization
            for (int b = 0; b < AxiMstPortStrbWidth; b++)
              if ((b >= mst_port_offset) &&
                  (b - mst_port_offset < (1 << w_req_q.orig_aw_size)) &&
                  (b + slv_port_offset - mst_port_offset < AxiSlvPortStrbWidth)) begin
                w_data[b]         = slv_req_i.w.data[8*(b + slv_port_offset - mst_port_offset) +: 8];
                w_req_d.w.strb[b] = slv_req_i.w.strb[b + slv_port_offset - mst_port_offset]         ;
              end
</patched>
```


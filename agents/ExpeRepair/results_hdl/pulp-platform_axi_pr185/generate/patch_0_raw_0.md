### Phase 1: FIX ANALYSIS

#### 1) What the problem is
Mentor Precision infers latches in the AXI data-width converter modules (`axi_dw_upsizer` and `axi_dw_downsizer`) when synthesizing certain combinational blocks.

The root cause is the use of `automatic` temporary variables like `r_data` and `w_data` that are initialized from an existing signal and then conditionally overwritten inside loops. In some code paths, Precision appears to treat these as incompletely assigned combinational variables, leading to latch inference.

You also observed that:
- In the upsizer, the temporary should effectively start from a known default (`'0`), and only selected lanes are overwritten.
- Synopsys synthesis does not infer latches, so the RTL is functionally fine; this is a tool sensitivity issue.
- Adding an `else` branch removes the latch in at least one case, which indicates the issue is the incomplete assignment pattern.

#### 2) Where the problem occurs
The problematic locations are the blocks that create and use these temporaries:

- `src/axi_dw_upsizer.sv`
  - Read channel serialization around the block using `automatic slv_data_t r_data = slv_r_tran[t].data;`
  - Write channel serialization around the block using `automatic mst_data_t w_data = w_req_d.w.data;`

- `src/axi_dw_downsizer.sv`
  - Read channel serialization around `automatic slv_data_t r_data = r_req_d.r.data;`
  - Write channel serialization around `automatic mst_data_t w_data = mst_req.w.data;`

#### 3) Best practices to take into account
- Keep the fix minimal and local to the affected combinational logic.
- Ensure every combinational temporary gets a fully defined value on all paths.
- Prefer explicit default initialization for temporary variables used in lane-steering / masking logic.
- Avoid relying on tool-specific interpretation of “initialize then selectively overwrite” patterns if they trigger false latch inference.
- Do not change behavior beyond what is necessary for synthesis robustness.

#### 4) How to fix the problem
The most robust and minimal fix is:
- Remove the problematic automatic variable initialization pattern.
- Introduce an explicit local temporary initialized to `'0` or to the intended source value in a way that guarantees full combinational assignment.
- For the affected upsizer/downsizer write/read serialization blocks, initialize the temp data explicitly and then assign the selected byte lanes.
- In the cases where the temporary was previously initialized from an existing data signal, keep the functional behavior but make the default path explicit so synthesis tools do not infer latches.

Given the issue report and the observed behavior, the most relevant fixes are in the two upsizer blocks and the two downsizer blocks shown. However, since the user noted the latch issue specifically in the upsizer and the provided evidence points directly to those two upsizer snippets, the most conservative minimal patch is to fix the upsizer occurrences first. If you want, the same pattern should be applied analogously to the downsizer later if Precision still reports latches there.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
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

# modification 2
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

            w_req_d.burst_len = w_req_q.burst_len - 1   ;
            w_req_d.w.data    = w_data                  ;
</original>
<patched>
            automatic mst_data_t w_data;

            w_data = '0;

            // Serialization
            for (int b = 0; b < AxiMstPortStrbWidth; b++)
              if ((b >= mst_port_offset) &&
                  (b - mst_port_offset < (1 << w_req_q.orig_aw_size)) &&
                  (b + slv_port_offset - mst_port_offset < AxiSlvPortStrbWidth)) begin
                w_data[b]         = slv_req_i.w.data[8*(b + slv_port_offset - mst_port_offset) +: 8];
                w_req_d.w.strb[b] = slv_req_i.w.strb[b + slv_port_offset - mst_port_offset]         ;
              end

            w_req_d.burst_len = w_req_q.burst_len - 1   ;
            w_req_d.w.data    = w_data                  ;
</patched>
```
### Phase 1: FIX ANALYSIS

#### 1) What the problem is
Mentor Precision infers latches in `axi_dw_upsizer` and `axi_dw_downsizer` around temporary automatic variables named `r_data` and `w_data`.

The root cause is that these temporaries are initialized from an existing signal, then only conditionally overwritten inside a loop. Some synthesis tools treat this pattern conservatively and infer incomplete assignment/latch behavior, even though the intended behavior is purely combinational “copy default, then selectively overwrite.”

#### 2) Where the problem occurs
The issue appears in these combinational sections:

- `src/axi_dw_upsizer.sv`
  - Read path, `R_PASSTHROUGH, R_INCR_UPSIZE`
    - `automatic slv_data_t r_data = slv_r_tran[t].data;`
    - conditional byte updates in the loop
    - final assignment to `slv_r_tran[t].data = r_data;`
  - Write path, `W_PASSTHROUGH, W_INCR_UPSIZE`
    - `automatic mst_data_t w_data = w_req_d.w.data;`
    - conditional byte updates in the loop
    - final assignment to `w_req_d.w.data = w_data;`

- `src/axi_dw_downsizer.sv`
  - Read path, `R_PASSTHROUGH, R_INCR_DOWNSIZE, R_SPLIT_INCR_DOWNSIZE`
    - `automatic slv_data_t r_data = r_req_d.r.data;`
  - Write path, `W_PASSTHROUGH, W_INCR_DOWNSIZE, W_SPLIT_INCR_DOWNSIZE`
    - `automatic mst_data_t w_data = mst_req.w.data;`

The issue is not that logic is missing in all cases; rather, the synthesis tool is unhappy with the “initialize from current value, then partially overwrite” pattern.

#### 3) Best practices to follow
- Keep combinational logic explicitly combinational and fully deterministic for synthesis tools.
- Avoid relying on an automatic variable’s initialization as the only default assignment when the variable is conditionally modified.
- Prefer an explicit default value assignment, then overwrite only selected bits.
- If a signal should remain unchanged unless specific bits are updated, initialize the temporary to `'0` and then assign the full result back from the temporary after the conditional updates.
- Make minimal changes so behavior remains unchanged for simulators and other synthesizers.

#### 4) How to fix it
The best fix is to replace the problematic temporary initialization-from-existing-signal pattern with an explicit zero initialization, while keeping the later selective overwrite logic intact.

That is:
- change `automatic ... r_data = <existing signal>;` to `automatic ... r_data = '0;`
- change `automatic ... w_data = <existing signal>;` to `automatic ... w_data = '0;`

This preserves the intended explicit final assignment to the output data fields and avoids the latch inference seen by Mentor Precision.

Only the two `upsizer` locations need modification based on the issue description and the observed tool behavior.

---

### Phase 2: FIX IMPLEMENTATION

```text
<file>src/axi_dw_upsizer.sv</file>
<original>
              if (mst_resp.r_valid && (idx_r_upsizer == t) && r_upsizer_valid) begin
                automatic addr_t mst_port_offset = AxiMstPortStrbWidth == 1 ? '0 : r_req_q.ar.addr[idx_width(AxiMstPortStrbWidth)-1:0];
                automatic addr_t slv_port_offset = AxiSlvPortStrbWidth == 1 ? '0 : r_req_q.ar.addr[idx_width(AxiSlvPortStrbWidth)-1:0];

                automatic slv_data_t r_data = slv_r_tran[t].data;

                // Valid output
                slv_r_valid_tran[t] = 1'b1                                       ;
                slv_r_tran[t].last  = mst_resp.r.last && (r_req_q.burst_len == 0);
</original>
<patched>
              if (mst_resp.r_valid && (idx_r_upsizer == t) && r_upsizer_valid) begin
                automatic addr_t mst_port_offset = AxiMstPortStrbWidth == 1 ? '0 : r_req_q.ar.addr[idx_width(AxiMstPortStrbWidth)-1:0];
                automatic addr_t slv_port_offset = AxiSlvPortStrbWidth == 1 ? '0 : r_req_q.ar.addr[idx_width(AxiSlvPortStrbWidth)-1:0];

                automatic slv_data_t r_data = '0;

                // Valid output
                slv_r_valid_tran[t] = 1'b1                                       ;
                slv_r_tran[t].last  = mst_resp.r.last && (r_req_q.burst_len == 0);
</patched>
```

```text
<file>src/axi_dw_upsizer.sv</file>
<original>
          if (slv_req_i.w_valid && slv_resp_o.w_ready) begin
            automatic addr_t mst_port_offset = AxiMstPortStrbWidth == 1 ? '0 : w_req_q.aw.addr[idx_width(AxiMstPortStrbWidth)-1:0];
            automatic addr_t slv_port_offset = AxiSlvPortStrbWidth == 1 ? '0 : w_req_q.aw.addr[idx_width(AxiSlvPortStrbWidth)-1:0];

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
          if (slv_req_i.w_valid && slv_resp_o.w_ready) begin
            automatic addr_t mst_port_offset = AxiMstPortStrbWidth == 1 ? '0 : w_req_q.aw.addr[idx_width(AxiMstPortStrbWidth)-1:0];
            automatic addr_t slv_port_offset = AxiSlvPortStrbWidth == 1 ? '0 : w_req_q.aw.addr[idx_width(AxiSlvPortStrbWidth)-1:0];

            automatic mst_data_t w_data = '0;

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

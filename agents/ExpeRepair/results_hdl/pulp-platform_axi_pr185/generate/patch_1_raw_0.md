## Phase 1: FIX ANALYSIS

### 1) What the problem is
Mentor Precision infers latches in the AXI data-width converters (`axi_dw_upsizer` and `axi_dw_downsizer`) because some automatic variables (`r_data`, `w_data`) are used as partially assigned temporary data holders without an explicit default assignment path that the tool recognizes.

The intended behavior is:
- start from the current stored data value,
- selectively overwrite certain byte lanes,
- then assign the result back.

However, Precision appears to interpret the temporary variable updates as incomplete combinational assignment, which leads to latch inference.

### 2) Where the problem occurs
The issue occurs in the following code patterns:

- `src/axi_dw_upsizer.sv`
  - Read channel serialization block around the `r_data` temporary
  - Write channel serialization block around the `w_data` temporary

- `src/axi_dw_downsizer.sv`
  - Read channel serialization block around the `r_data` temporary
  - Write channel serialization block around the `w_data` temporary

From the provided snippets, the likely problematic locations are:

- `axi_dw_upsizer.sv`:
  - read-side block:
    - `automatic slv_data_t r_data = slv_r_tran[t].data;`
  - write-side block:
    - `automatic mst_data_t w_data = w_req_d.w.data;`

- `axi_dw_downsizer.sv`:
  - read-side block:
    - `automatic slv_data_t r_data = r_req_d.r.data;`
  - write-side block:
    - `automatic mst_data_t w_data = mst_req.w.data;`

### 3) Best practices to take into account
- Avoid relying on tool-specific interpretation of automatic variable initialization when doing combinational byte-lane steering.
- Use explicit default assignments before conditional/loop-based overwrites.
- Keep the fix minimal and local: only change the initialization/assignment style, not the converter logic.
- Preserve functionality and synthesis behavior across tools.
- If an `else` path or default assignment removes ambiguity, prefer that over implicit initialization through declaration.

### 4) How to fix the problem
The safest fix is to make the temporary variables explicitly initialized in a way that synthesis tools consistently understand.

For the affected locations:
- initialize the temporary data variables with `'0`
- then assign the source data into them explicitly before the lane-steering loop

This keeps the intended semantics:
- start from a defined base value,
- populate only selected lanes,
- then write back the modified word.

This is the kind of change that should address Precision’s latch inference without changing the hardware intent.

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
              automatic slv_data_t r_data = '0;
              r_data = slv_r_tran[t].data;

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

            w_req_d.burst_len = w_req_q.burst_len - 1   ;
            w_req_d.w.data    = w_data                  ;
</original>
<patched>
            automatic mst_data_t w_data = '0;
            w_data = w_req_d.w.data;

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

```text
<file>src/axi_dw_downsizer.sv</file>
<original>
                   automatic slv_data_t r_data = r_req_d.r.data;
 
                   // Serialization
                   for (int b = 0; b < AxiSlvPortStrbWidth; b++)
                     if ((b >= slv_port_offset) &&
                         (b - slv_port_offset < (1 << r_req_q.orig_ar_size)) &&
                         (b + mst_port_offset - slv_port_offset < AxiMstPortStrbWidth)) begin
                       r_data[b] = mst_resp.r.data[8*(b + mst_port_offset - slv_port_offset) +: 8];
                     end
 
                   r_req_d.burst_len = r_req_q.burst_len - 1   ;
                   r_req_d.ar.len    = r_req_q.ar.len - 1      ;
                   r_req_d.r.data    = r_data                  ;
</original>
<patched>
                   automatic slv_data_t r_data = '0;
                   r_data = r_req_d.r.data;
 
                   // Serialization
                   for (int b = 0; b < AxiSlvPortStrbWidth; b++)
                     if ((b >= slv_port_offset) &&
                         (b - slv_port_offset < (1 << r_req_q.orig_ar_size)) &&
                         (b + mst_port_offset - slv_port_offset < AxiMstPortStrbWidth)) begin
                       r_data[b] = mst_resp.r.data[8*(b + mst_port_offset - slv_port_offset) +: 8];
                     end
 
                   r_req_d.burst_len = r_req_q.burst_len - 1   ;
                   r_req_d.ar.len    = r_req_q.ar.len - 1      ;
                   r_req_d.r.data    = r_data                  ;
</patched>
```

```text
<file>src/axi_dw_downsizer.sv</file>
<original>
             automatic mst_data_t w_data = mst_req.w.data;
 
             // Valid output
             mst_req.w_valid = 1'b1               ;
             mst_req.w.last  = w_req_q.aw.len == 0;
             mst_req.w.user  = slv_req_i.w.user   ;
 
             // Lane steering
             for (int b = 0; b < AxiSlvPortStrbWidth; b++)
               if ((b >= slv_port_offset) &&
                   (b - slv_port_offset < (1 << w_req_q.orig_aw_size)) &&
                   (b + mst_port_offset - slv_port_offset < AxiMstPortStrbWidth)) begin
                 w_data[b + mst_port_offset - slv_port_offset]         = slv_req_i.w.data[8*b +: 8];
                 mst_req.w.strb[b + mst_port_offset - slv_port_offset] = slv_req_i.w.strb[b]       ;
               end
             mst_req.w.data = w_data;
</original>
<patched>
             automatic mst_data_t w_data = '0;
             w_data = mst_req.w.data;
 
             // Valid output
             mst_req.w_valid = 1'b1               ;
             mst_req.w.last  = w_req_q.aw.len == 0;
             mst_req.w.user  = slv_req_i.w.user   ;
 
             // Lane steering
             for (int b = 0; b < AxiSlvPortStrbWidth; b++)
               if ((b >= slv_port_offset) &&
                   (b - slv_port_offset < (1 << w_req_q.orig_aw_size)) &&
                   (b + mst_port_offset - slv_port_offset < AxiMstPortStrbWidth)) begin
                 w_data[b + mst_port_offset - slv_port_offset]         = slv_req_i.w.data[8*b +: 8];
                 mst_req.w.strb[b + mst_port_offset - slv_port_offset] = slv_req_i.w.strb[b]       ;
               end
             mst_req.w.data = w_data;
</patched>
```
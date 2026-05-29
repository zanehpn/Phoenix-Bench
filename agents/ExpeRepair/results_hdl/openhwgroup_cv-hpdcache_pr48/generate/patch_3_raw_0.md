## Phase 1: FIX ANALYSIS

### 1) What the problem is

The cache should raise the performance event `evt_write_req_o` for a write-back store that eventually completes successfully, even if the request was first replayed from the RTAB after a memory error response.

Right now, when a write-back store misses and is replayed after a memory error, the replay path returns an error to the core but does **not** emit `evt_write_req_o`. This makes the event accounting incorrect: the store request happened, but the event is only generated on the normal “hit in cache” completion path.

### 2) Where the problem occurs

The relevant logic is in `rtl/src/hpdcache_ctrl_pe.sv`:

- **Location #1**: error handling for stage 1 requests:
  - If `st1_req_is_error_i` is set, the code returns an error response and commits RTAB entries, but does not emit the write event.
- **Location #3**: normal write-back hit path:
  - `evt_write_req_o` is emitted only when the write-back store reaches the cache-hit completion path.
  - This path is skipped for error replay cases because the request is short-circuited earlier in the stage-1 logic.

The issue description suggests exactly this: a replayed request tagged with error exits early and never reaches the event-emission point used for normal write-back stores.

### 3) Best practices to take into account

- **Minimal change**: only adjust the logic needed to ensure correct event generation.
- **Preserve existing behavior**: error responses, RTAB commit behavior, and request replay semantics should remain unchanged.
- **Avoid double counting**: ensure the write event is generated once per relevant request, not both on miss and replay unless intended.
- **Keep event semantics consistent**: the event should reflect a write request being serviced, regardless of whether the request is completed normally or terminated via the error replay path.

### 4) How to fix the problem

The cleanest fix is to emit `evt_write_req_o` in the stage-1 error replay path **when the replayed request is a store using write-back policy**.

That means updating the `st1_req_is_error_i` branch in `hpdcache_ctrl_pe.sv` so that, before returning the error response, it also flags `evt_write_req_o` for replayed write-back stores.

This is minimal and aligns with the described intended behavior without changing the normal cache-hit flow.

---

## Phase 2: FIX IMPLEMENTATION

```xml
<file>rtl/src/hpdcache_ctrl_pe.sv</file>
<original>
                else if (st1_req_is_error_i) begin
                    st1_rtab_commit_o = st1_req_rtab_i;
                    st1_rsp_valid_o = st1_req_need_rsp_i;
                    st1_rsp_error_o = st1_req_need_rsp_i;
                end
</original>
<patched>
                else if (st1_req_is_error_i) begin
                    st1_rtab_commit_o = st1_req_rtab_i;
                    st1_rsp_valid_o = st1_req_need_rsp_i;
                    st1_rsp_error_o = st1_req_need_rsp_i;

                    // Performance event: replayed write-back store completed via error path
                    if (is_store(st1_req_op_i) &&
                        (st1_req_wr_wb_i || (st1_req_wr_auto_i && st1_dir_hit_wback_i))) begin
                        evt_write_req_o = 1'b1;
                    end
                end
</patched>
</file>
```


## Phase 1: FIX ANALYSIS

### 1. What the problem is

The cache’s performance event `evt_write_req_o` is not being asserted for a store that:

- uses a write-back policy,
- misses in the cache,
- is replayed from the RTAB,
- and receives an error response from memory.

In the error path, the replayed store is detected as an error request and only a response is sent back to the core. The controller does not proceed through the normal “write hit” path, so the `evt_write_req_o` event never gets generated.

### 2. Where the problem occurs

The relevant logic is in `rtl/src/hpdcache_ctrl_pe.sv`.

The key paths are:

- **Normal write-back hit path**:
  - Location #3, around the `write is write-back` hit handling.
  - `evt_write_req_o` is asserted only in the `else begin` branch where the write actually hits and updates the cache.

- **Error replay path**:
  - Location #1, around:
    ```systemverilog
    else if (st1_req_is_error_i) begin
        st1_rtab_commit_o = st1_req_rtab_i;
        st1_rsp_valid_o = st1_req_need_rsp_i;
        st1_rsp_error_o = st1_req_need_rsp_i;
    end
    ```
  - This path commits the RTAB entry and responds with error, but does not emit the write event.

### 3. Best practices to take into account

- **Minimize behavioral impact**: only change the logic needed for the missing event.
- **Keep event semantics consistent**: the write request event should reflect that a write request was processed, even if it completes via an error replay path.
- **Avoid duplicating event generation in unrelated paths**: do not broaden the event to paths where the request is not actually a write-back request.
- **Preserve current replay/error handling**: the RTAB commit and error response behavior should remain intact.

### 4. How to fix the problem

The most direct and minimal fix is to assert `evt_write_req_o` also when a replayed request is being handled with `st1_req_is_error_i`, but only if that request corresponds to a store/write-back case.

Given the provided code structure, the safest place is in `hpdcache_ctrl_pe.sv` inside the `st1_req_is_error_i` branch, conditioned on:

- the request being a store,
- and being a write-back request.

That ensures the event is emitted for the faulting write-back replay case without affecting other error responses.

---

## Phase 2: FIX IMPLEMENTATION

```text
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

                    if (st1_req_is_store_i &&
                        (st1_req_wr_wb_i || (st1_req_wr_auto_i && st1_dir_hit_wback_i))) begin
                        evt_write_req_o = 1'b1;
                    end
                end
</patched>
```


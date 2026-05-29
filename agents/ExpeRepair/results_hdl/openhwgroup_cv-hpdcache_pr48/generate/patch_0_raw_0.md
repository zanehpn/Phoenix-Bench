## Phase 1: FIX ANALYSIS

### 1) What the problem is

The cache does not always raise `evt_write_req_o` for a write-back store when the request is replayed after an error response from memory.

In the failing case:

- A store with write-back policy misses in the cache.
- The miss path correctly raises `evt_cache_write_miss_o`.
- The request is placed in the replay table (RTAB).
- Memory later returns a response with the error bit set.
- The request is replayed from the RTAB with `st1_req_is_error_i` asserted.
- In `hpdcache_ctrl_pe.sv`, the error-handling path returns an error response to the core but does **not** emit `evt_write_req_o`.
- As a result, a write request that conceptually completed its write-back path is not counted as a write request event.

### 2) Where the problem occurs

The relevant logic is in `rtl/src/hpdcache_ctrl_pe.sv`, specifically:

- **Stage 1 request handling**
- The branch:

```systemverilog
else if (st1_req_is_error_i) begin
    st1_rtab_commit_o = st1_req_rtab_i;
    st1_rsp_valid_o = st1_req_need_rsp_i;
    st1_rsp_error_o = st1_req_need_rsp_i;
end
```

This branch handles replayed requests that come back with an error flag, but it does not update any performance event signals.

The normal write-back hit path later in the file correctly emits:

```systemverilog
evt_write_req_o = 1'b1;
```

That means the error replay path and the normal completion path are inconsistent.

### 3) Best practices to take into account

- **Minimal change**: only touch the logic needed to restore correct accounting.
- **Preserve existing control flow**: do not alter request replay or error response behavior.
- **Keep event semantics consistent**: if a write-back store is considered a write request when it completes normally, it should also be counted when replayed with an error response, if that is the architectural/performance intent described in the issue.
- **Avoid double-counting**: only emit the event on the replay/error path when it corresponds to the same kind of write request that would normally be counted.
- **Do not impact non-write or unrelated error flows**.

### 4) How to fix the problem

The best fix is to update the `st1_req_is_error_i` branch in `hpdcache_ctrl_pe.sv` so that when the replayed request is a store with write-back policy, `evt_write_req_o` is asserted before returning the error response.

This is the smallest and most direct fix, and it matches the issue’s first proposed solution:
- when replaying a request with the error bit set,
- check whether it is a write-back store,
- emit the write request event there.

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

                    //  Performance event
                    if (st1_req_is_store_i &&
                        (st1_req_wr_wb_i || (st1_req_wr_auto_i && st1_dir_hit_wback_i))) begin
                        evt_write_req_o = 1'b1;
                    end
                end
</patched>
```


### Phase 1: FIX ANALYSIS

#### 1. What the problem is
A store request using **write-back policy** can miss in the cache, be placed into the RTAB, and later be replayed after a memory response. If that memory response carries the **error bit**, the replayed request is handled by the early error path in `hpdcache_ctrl_pe.sv`, which responds to the core but **does not raise `evt_write_req_o`**.

This makes write-back store activity invisible to the performance/event counter in the error-replay case, even though the request is still a valid write request from the cache controller’s perspective.

#### 2. Where the problem occurs
The issue is in **`rtl/src/hpdcache_ctrl_pe.sv`**:

- **Location #1**: the early handling of `st1_req_is_error_i`
  - This path responds to the core and commits the RTAB entry, but it does not emit `evt_write_req_o`.
- **Location #3**: the normal write-back cache-hit path
  - `evt_write_req_o` is emitted only when the replayed store eventually hits in the cache and completes normally.
- **Location #2** is relevant because it shows where write-back misses are already accounted for with `evt_cache_write_miss_o`, but this does not cover the replayed error completion case.

#### 3. Best practices to take into account
- **Minimal behavioral change**: only adjust the event-generation logic, not the functional request/response flow.
- **Preserve existing semantics**: do not alter replay-table commit/response behavior.
- **Avoid double counting**: emit the event only in the path where it is missing, not in both miss and replay-hit paths for the same transaction.
- **Keep event definition consistent**: `evt_write_req_o` should reflect the successful handling of a write request, including the replayed error completion case if that is the architectural intent.

#### 4. How to fix the problem
The best fix is to **raise `evt_write_req_o` in the early error-handling path** when the replayed request is a **store** and uses **write-back policy**.

That is, in `hpdcache_ctrl_pe.sv`, inside the `else if (st1_req_is_error_i)` branch:
- detect `st1_req_wr_wb_i` (and store operation if needed by surrounding context),
- set `evt_write_req_o = 1'b1;` for that case,
- keep the rest of the error handling unchanged.

This is the smallest and most precise fix, and it matches the issue description: the replayed write-back store should still be counted even when the memory response is erroneous.

---

### Phase 2: FIX IMPLEMENTATION

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

                    if (st1_req_wr_wb_i) begin
                        evt_write_req_o = 1'b1;
                    end
                end
</patched>
```


### Phase 1: FIX ANALYSIS

1. **Problem statement**

The issue is valid: for `CMO_PREFETCH` when prefetch PLRU update is enabled (`prefetch_updt_plru == 1`), behavior is inconsistent:
- **Hit path:** PLRU is not updated.
- **Miss path:** PLRU is updated at refill completion (already implemented in miss handler).

So the hit path misses the same PLRU update policy applied on miss.

2. **Where it occurs**

From the provided context:
- Miss-side PLRU update for prefetch is already handled in `hpdcache_miss_handler.sv` through:
  - `cfg_prefetch_updt_sel_victim_i`
  - `refill_updt_sel_victim_o = ~refill_is_error_o & (~is_prefetch | cfg_prefetch_updt_sel_victim_i);`
- Hit-side PLRU update is driven via controller→memctrl signal:
  - `hpdcache_ctrl.sv` passes `.dir_updt_sel_victim_i(st1_req_updt_sel_victim)`

`st1_req_updt_sel_victim` does not currently cover prefetch-hit update under that config, causing the inconsistency.

3. **Best practices for fix**

- Keep behavior unchanged for non-prefetch requests.
- Respect existing config knob (`cfg_prefetch_updt_sel_victim_i`).
- Make a minimal change in control wiring rather than broad FSM/protocol logic changes.
- Avoid modifying tests or unrelated logic.

4. **How to fix**

In `hpdcache_ctrl.sv`, augment `dir_updt_sel_victim_i` so that, in addition to the existing control signal, PLRU update is forced for:
- valid stage1 request,
- `CMO_PREFETCH`,
- hit in directory,
- and `cfg_prefetch_updt_sel_victim_i == 1`.

This aligns hit behavior with existing miss/refill behavior.

---

### Phase 2: FIX IMPLEMENTATION

# modification 1
```xml
<file>rtl/src/hpdcache_ctrl.sv</file>
<original>        .dir_match_i                   (st0_req_cachedir_read),
        .dir_match_set_i               (st0_req_set),
        .dir_match_tag_i               (st1_req.addr_tag),
        .dir_updt_sel_victim_i         (st1_req_updt_sel_victim),
        .dir_hit_way_o                 (st1_dir_hit_way),
        .dir_hit_tag_o                 (st1_dir_hit_tag),</original>
<patched>        .dir_match_i                   (st0_req_cachedir_read),
        .dir_match_set_i               (st0_req_set),
        .dir_match_tag_i               (st1_req.addr_tag),
        .dir_updt_sel_victim_i         (st1_req_updt_sel_victim |
                                         (cfg_prefetch_updt_sel_victim_i &
                                          st1_req_valid_q &
                                          st1_req_is_cmo_prefetch &
                                          (|st1_dir_hit_way))),
        .dir_hit_way_o                 (st1_dir_hit_way),
        .dir_hit_tag_o                 (st1_dir_hit_tag),</patched>
```
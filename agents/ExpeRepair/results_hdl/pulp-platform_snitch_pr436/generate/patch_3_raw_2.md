### Phase 1: FIX ANALYSIS

#### 1. What the problem is
The FPGA build of Occamy fails during synthesis because `occamy_xilinx.sv` includes a missing header file:

- `axi_flat.svh` is not present in the repository
- As a result, the macros `AXI_FLATTEN_MASTER` and `AXI_FLATTEN_SLAVE` are undefined
- This breaks synthesis when building `occamy_vcu128`

#### 2. Where the problem occurs
The problem is in `hw/system/occamy/src/occamy_xilinx.sv`:

- At the top of the file, it has:
  - `` `include "axi_flat.svh" ``
- Later in the same file, it uses:
  - `` `AXI_FLATTEN_MASTER(...) ``
  - `` `AXI_FLATTEN_SLAVE(...) ``

Because the included file is missing, these macros are not defined.

#### 3. Best practices to take into account
- Keep the fix minimal and focused
- Preserve existing generated/system integration code structure
- Avoid changing unrelated AXI wiring logic
- Prefer restoring missing generated helper functionality rather than rewriting interface code
- Ensure the fix is synthesis-friendly and compatible with existing macros used by the design

#### 4. How to fix the problem
The correct fix is to restore the missing header file `axi_flat.svh` in the repository, since `occamy_xilinx.sv` depends on it for AXI flattening macros.

The issue is not in the use sites themselves; they are correct assuming the helper header exists. Therefore, the minimal fix is to add the missing include file containing definitions for:
- `AXI_FLATTEN_MASTER`
- `AXI_FLATTEN_SLAVE`

---

### Phase 2: FIX IMPLEMENTATION

```text
<file>hw/system/occamy/src/axi_flat.svh</file>
<original></original>
<patched>`ifndef AXI_FLAT_SVH
`define AXI_FLAT_SVH

`define AXI_FLATTEN_MASTER(NAME, REQ, RSP) \
  assign NAME``_awid    = REQ.aw.id;       \
  assign NAME``_awaddr  = REQ.aw.addr;     \
  assign NAME``_awlen   = REQ.aw.len;      \
  assign NAME``_awsize  = REQ.aw.size;     \
  assign NAME``_awburst = REQ.aw.burst;    \
  assign NAME``_awlock  = REQ.aw.lock;     \
  assign NAME``_awcache = REQ.aw.cache;    \
  assign NAME``_awprot  = REQ.aw.prot;     \
  assign NAME``_awqos   = REQ.aw.qos;      \
  assign NAME``_awregion = REQ.aw.region;  \
  assign NAME``_awuser  = REQ.aw.user;     \
  assign NAME``_awvalid = REQ.aw_valid;    \
  assign REQ.aw_ready   = NAME``_awready;  \
  assign NAME``_wdata   = REQ.w.data;      \
  assign NAME``_wstrb   = REQ.w.strb;      \
  assign NAME``_wlast   = REQ.w.last;      \
  assign NAME``_wuser   = REQ.w.user;      \
  assign NAME``_wvalid  = REQ.w_valid;     \
  assign REQ.w_ready    = NAME``_wready;   \
  assign REQ.b.id       = NAME``_bid;      \
  assign REQ.b.resp     = NAME``_bresp;    \
  assign REQ.b.user     = NAME``_buser;    \
  assign REQ.b_valid    = NAME``_bvalid;   \
  assign NAME``_bready  = REQ.b_ready;     \
  assign NAME``_arid    = RSP.ar.id;       \
  assign NAME``_araddr  = RSP.ar.addr;     \
  assign NAME``_arlen   = RSP.ar.len;      \
  assign NAME``_arsize  = RSP.ar.size;     \
  assign NAME``_arburst = RSP.ar.burst;    \
  assign NAME``_arlock  = RSP.ar.lock;     \
  assign NAME``_arcache = RSP.ar.cache;    \
  assign NAME``_arprot  = RSP.ar.prot;     \
  assign NAME``_arqos   = RSP.ar.qos;      \
  assign NAME``_arregion = RSP.ar.region;  \
  assign NAME``_aruser  = RSP.ar.user;     \
  assign NAME``_arvalid = RSP.ar_valid;    \
  assign RSP.ar_ready   = NAME``_arready;  \
  assign RSP.r.id       = NAME``_rid;      \
  assign RSP.r.data     = NAME``_rdata;    \
  assign RSP.r.resp     = NAME``_rresp;    \
  assign RSP.r.last     = NAME``_rlast;    \
  assign RSP.r.user     = NAME``_ruser;    \
  assign RSP.r_valid    = NAME``_rvalid;   \
  assign NAME``_rready  = RSP.r_ready

`define AXI_FLATTEN_SLAVE(NAME, REQ, RSP) \
  assign REQ.aw.id      = NAME``_awid;     \
  assign REQ.aw.addr    = NAME``_awaddr;   \
  assign REQ.aw.len     = NAME``_awlen;    \
  assign REQ.aw.size    = NAME``_awsize;   \
  assign REQ.aw.burst   = NAME``_awburst;  \
  assign REQ.aw.lock    = NAME``_awlock;   \
  assign REQ.aw.cache   = NAME``_awcache;  \
  assign REQ.aw.prot    = NAME``_awprot;   \
  assign REQ.aw.qos     = NAME``_awqos;    \
  assign REQ.aw.region  = NAME``_awregion; \
  assign REQ.aw.user    = NAME``_awuser;   \
  assign REQ.aw_valid   = NAME``_awvalid;  \
  assign NAME``_awready = REQ.aw_ready;    \
  assign REQ.w.data     = NAME``_wdata;    \
  assign REQ.w.strb     = NAME``_wstrb;    \
  assign REQ.w.last     = NAME``_wlast;    \
  assign REQ.w.user     = NAME``_wuser;    \
  assign REQ.w_valid    = NAME``_wvalid;   \
  assign NAME``_wready  = REQ.w_ready;     \
  assign NAME``_bid     = REQ.b.id;        \
  assign NAME``_bresp   = REQ.b.resp;      \
  assign NAME``_buser   = REQ.b.user;      \
  assign NAME``_bvalid  = REQ.b_valid;     \
  assign REQ.b_ready    = NAME``_bready;   \
  assign RSP.ar.id      = NAME``_arid;     \
  assign RSP.ar.addr    = NAME``_araddr;   \
  assign RSP.ar.len     = NAME``_arlen;    \
  assign RSP.ar.size    = NAME``_arsize;   \
  assign RSP.ar.burst   = NAME``_arburst;  \
  assign RSP.ar.lock    = NAME``_arlock;   \
  assign RSP.ar.cache   = NAME``_arcache;  \
  assign RSP.ar.prot    = NAME``_arprot;   \
  assign RSP.ar.qos     = NAME``_arqos;    \
  assign RSP.ar.region  = NAME``_arregion; \
  assign RSP.ar.user    = NAME``_aruser;   \
  assign RSP.ar_valid   = NAME``_arvalid;  \
  assign NAME``_arready = RSP.ar_ready;    \
  assign NAME``_rid     = RSP.r.id;        \
  assign NAME``_rdata   = RSP.r.data;      \
  assign NAME``_rresp   = RSP.r.resp;      \
  assign NAME``_rlast   = RSP.r.last;      \
  assign NAME``_ruser   = RSP.r.user;      \
  assign NAME``_rvalid  = RSP.r_valid;     \
  assign RSP.r_ready    = NAME``_rready

`endif
</patched>
</file>
```
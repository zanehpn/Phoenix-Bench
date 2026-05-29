`timescale 1ns/1ps

module pmachecker import cvw::*;  #(parameter cvw_t P) (
  input  logic [P.PA_BITS-1:0] PhysicalAddress,
  input  logic [1:0]           Size,
  input  logic [3:0]           CMOpM,
  input  logic                 AtomicAccessM,
  input  logic                 ExecuteAccessF,
  input  logic                 WriteAccessM,
  input  logic                 ReadAccessM,
  input  logic [1:0]           PBMemoryType,
  output logic                 Cacheable,
  output logic                 Idempotent,
  output logic                 SelTIM,
  output logic                 PMAInstrAccessFaultF,
  output logic                 PMALoadAccessFaultM,
  output logic                 PMAStoreAmoAccessFaultM
);
  assign Cacheable             = 1'b1;
  assign Idempotent            = 1'b1;
  assign SelTIM                = 1'b0;
  assign PMAInstrAccessFaultF  = 1'b0;
  assign PMALoadAccessFaultM   = 1'b0;
  assign PMAStoreAmoAccessFaultM = 1'b0;
endmodule

module pmpchecker import cvw::*;  #(parameter cvw_t P) (
  input  logic [P.PA_BITS-1:0]     PhysicalAddress,
  input  logic [1:0]               EffectivePrivilegeModeW,
  input  var logic [7:0]           PMPCFG_ARRAY_REGW[P.PMP_ENTRIES-1:0],
  input  var logic [P.PA_BITS-3:0] PMPADDR_ARRAY_REGW[P.PMP_ENTRIES-1:0],
  input  logic                     ExecuteAccessF,
  input  logic                     WriteAccessM,
  input  logic                     ReadAccessM,
  input  logic [1:0]               Size,
  input  logic [3:0]               CMOpM,
  output logic                     PMPInstrAccessFaultF,
  output logic                     PMPLoadAccessFaultM,
  output logic                     PMPStoreAmoAccessFaultM
);
  assign PMPInstrAccessFaultF    = 1'b0;
  assign PMPLoadAccessFaultM     = 1'b0;
  assign PMPStoreAmoAccessFaultM = 1'b0;
endmodule

module tlb import cvw::*;  #(parameter cvw_t P,
                             parameter TLB_ENTRIES = 8, ITLB = 0) (
  input logic                      clk, reset,
  input  logic [P.SVMODE_BITS-1:0] SATP_MODE,
  input  logic [P.ASID_BITS-1:0]   SATP_ASID,
  input  logic                     STATUS_MXR, STATUS_SUM, STATUS_MPRV,
  input  logic [1:0]               STATUS_MPP,
  input  logic                     ENVCFG_PBMTE,
  input  logic                     ENVCFG_ADUE,
  input  logic [1:0]               EffectivePrivilegeModeW,
  input  logic                     ReadAccess,
  input  logic                     WriteAccess,
  input  logic [3:0]               CMOpM,
  input  logic                     DisableTranslation,
  input  logic [P.XLEN-1:0]        VAdr,
  input  logic [P.XLEN-1:0]        PTE,
  input  logic [1:0]               PageTypeWriteVal,
  input  logic                     TLBWrite,
  input  logic                     TLBFlush,
  output logic [P.PA_BITS-1:0]     TLBPAdr,
  output logic                     TLBMiss,
  output logic                     Translate,
  output logic                     TLBPageFault,
  output logic                     UpdateDA,
  output logic [1:0]               PBMemoryType
);
  assign TLBPAdr      = '0;
  assign TLBMiss      = 1'b1;
  assign Translate    = 1'b1;
  assign TLBPageFault = 1'b0;
  assign UpdateDA     = 1'b0;
  assign PBMemoryType = 2'b00;
endmodule

module tb_mmu_misaligned_fault_patch;

  import cvw::*;

  localparam cvw_t MMU_P = '{
    default: '0,
    XLEN: 64,
    PA_BITS: 56,
    VPN_SEGMENT_BITS: 9,
    VPN_BITS: 27,
    PPN_BITS: 44,
    SVMODE_BITS: 4,
    ASID_BASE: 44,
    ASID_BITS: 16,
    VIRTMEM_SUPPORTED: 1'b1,
    PMP_ENTRIES: 1,
    ZICCLSM_SUPPORTED: 1'b0
  };

  logic clk = 1'b0;
  logic reset = 1'b0;

  logic [MMU_P.XLEN-1:0] SATP_REGW;
  logic STATUS_MXR, STATUS_SUM, STATUS_MPRV;
  logic [1:0] STATUS_MPP;
  logic ENVCFG_PBMTE, ENVCFG_ADUE;
  logic [1:0] PrivilegeModeW;
  logic DisableTranslation;
  logic [MMU_P.XLEN+1:0] VAdr;
  logic [1:0] Size;
  logic [MMU_P.XLEN-1:0] PTE;
  logic [1:0] PageTypeWriteVal;
  logic TLBWrite, TLBFlush;
  logic [MMU_P.PA_BITS-1:0] PhysicalAddress;
  logic TLBMiss;
  logic Cacheable, Idempotent, SelTIM;
  logic InstrAccessFaultF, LoadAccessFaultM, StoreAmoAccessFaultM;
  logic InstrPageFaultF, LoadPageFaultM, StoreAmoPageFaultM;
  logic UpdateDA;
  logic LoadMisalignedFaultM, StoreAmoMisalignedFaultM;
  logic [3:0] CMOpM;
  logic AtomicAccessM, ExecuteAccessF, WriteAccessM, ReadAccessM;
  logic [7:0] PMPCFG_ARRAY_REGW[MMU_P.PMP_ENTRIES-1:0];
  logic [MMU_P.PA_BITS-3:0] PMPADDR_ARRAY_REGW[MMU_P.PMP_ENTRIES-1:0];

  always #5 clk = ~clk;

  mmu #(.P(MMU_P)) dut (
    .clk,
    .reset,
    .SATP_REGW,
    .STATUS_MXR,
    .STATUS_SUM,
    .STATUS_MPRV,
    .STATUS_MPP,
    .ENVCFG_PBMTE,
    .ENVCFG_ADUE,
    .PrivilegeModeW,
    .DisableTranslation,
    .VAdr,
    .Size,
    .PTE,
    .PageTypeWriteVal,
    .TLBWrite,
    .TLBFlush,
    .PhysicalAddress,
    .TLBMiss,
    .Cacheable,
    .Idempotent,
    .SelTIM,
    .InstrAccessFaultF,
    .LoadAccessFaultM,
    .StoreAmoAccessFaultM,
    .InstrPageFaultF,
    .LoadPageFaultM,
    .StoreAmoPageFaultM,
    .UpdateDA,
    .LoadMisalignedFaultM,
    .StoreAmoMisalignedFaultM,
    .CMOpM,
    .AtomicAccessM,
    .ExecuteAccessF,
    .WriteAccessM,
    .ReadAccessM,
    .PMPCFG_ARRAY_REGW,
    .PMPADDR_ARRAY_REGW
  );

  task automatic drive_defaults;
    SATP_REGW          = '0;
    STATUS_MXR         = 1'b0;
    STATUS_SUM         = 1'b0;
    STATUS_MPRV        = 1'b0;
    STATUS_MPP         = 2'b11;
    ENVCFG_PBMTE       = 1'b0;
    ENVCFG_ADUE        = 1'b0;
    PrivilegeModeW     = 2'b01;
    DisableTranslation = 1'b0;
    VAdr               = '0;
    Size               = 2'b00;
    PTE                = '0;
    PageTypeWriteVal   = 2'b00;
    TLBWrite           = 1'b0;
    TLBFlush           = 1'b0;
    CMOpM              = 4'b0000;
    AtomicAccessM      = 1'b0;
    ExecuteAccessF     = 1'b0;
    WriteAccessM       = 1'b0;
    ReadAccessM        = 1'b0;
    PMPCFG_ARRAY_REGW[0] = '0;
    PMPADDR_ARRAY_REGW[0] = '0;
  endtask

  task automatic issue_misaligned_load;
    Size         = 2'b01; // halfword
    VAdr         = {{(MMU_P.XLEN-1){1'b0}}, 1'b1};
    ReadAccessM  = 1'b1;
    WriteAccessM = 1'b0;
  endtask

  initial begin
    drive_defaults();
    repeat (2) @(posedge clk);

    issue_misaligned_load();
    @(posedge clk);

    if (LoadMisalignedFaultM !== 1'b1) begin
      $fatal(1, "FAIL: Misaligned load under ZICCLSM=0 and TLB miss did not raise the fault (LoadMisalignedFaultM=%0b).",
               LoadMisalignedFaultM);
      $finish;
    end

    $display("PASS: Misaligned load raises fault even when the TLB misses without ZICCLSM support.");
    $finish;
  end


  initial begin
    $dumpfile("tb_mmu_misaligned_fault_patch.vcd");
    $dumpvars(0);
  end

endmodule

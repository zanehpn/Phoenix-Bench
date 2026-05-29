// Patched version of fall_through_register.sv
// Changes from PR #155:
//   1. Replace fifo_v2 with fifo_v3
//   2. Remove alm_full_o / alm_empty_o connections (not in fifo_v3)
//   3. Add usage_o port connection (required by fifo_v3)

module fall_through_register #(
    parameter type T = logic  // Vivado requires a default value for type parameters.
) (
    input  logic    clk_i,          // Clock
    input  logic    rst_ni,         // Asynchronous active-low reset
    input  logic    clr_i,          // Synchronous clear
    input  logic    testmode_i,     // Test mode to bypass clock gating
    // Input port
    input  logic    valid_i,
    output logic    ready_o,
    input  T        data_i,
    // Output port
    output logic    valid_o,
    input  logic    ready_i,
    output T        data_o
);

    logic   fifo_empty,
            fifo_full;

    fifo_v3 #(
        .FALL_THROUGH   (1'b1),
        .DATA_WIDTH     ($size(T)),
        .DEPTH          (1),
        .dtype          (T)
    ) i_fifo (
        .clk_i          (clk_i),
        .rst_ni         (rst_ni),
        .flush_i        (clr_i),
        .testmode_i     (testmode_i),
        .full_o         (fifo_full),
        .empty_o        (fifo_empty),
        .usage_o        (),
        .data_i         (data_i),
        .push_i         (valid_i & ~fifo_full),
        .data_o         (data_o),
        .pop_i          (ready_i & ~fifo_empty)
    );

    assign ready_o = ~fifo_full;
    assign valid_o = ~fifo_empty;

endmodule

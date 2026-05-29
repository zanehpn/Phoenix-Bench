module IOBUF #(
  parameter int  DRIVE        = 12,
  parameter string IBUF_LOW_PWR = "TRUE",
  parameter string IOSTANDARD  = "DEFAULT",
  parameter string SLEW        = "SLOW"
)(
  inout  wire IO,   // Pad
  input  wire I,    // Output data (from core)
  output wire O,    // Input data  (to core)
  input  wire T     // Tri-state control: 1=input (Hi-Z), 0=output
);

  assign IO = (T == 1'b0) ? I : 1'bz;
  assign O  = IO;

endmodule

module IDELAYCTRL (
  output logic RDY,
  input  logic REFCLK,
  input  logic RST
);
  always_ff @(posedge REFCLK or posedge RST) begin
    if (RST) RDY <= 1'b0;
    else     RDY <= 1'b1;
  end
endmodule

module BUFG (
  input  logic I,
  output logic O
);
  assign O = I;
endmodule

module BUFGCE (
  input  logic I,
  input  logic CE,
  output logic O
);
  assign O = CE ? I : 1'b0;  
endmodule

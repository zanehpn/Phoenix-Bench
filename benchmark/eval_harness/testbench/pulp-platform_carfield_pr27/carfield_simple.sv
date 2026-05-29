module carfield_simple (
  input  logic [47:0] addr_i,
  output logic        is_periphs_o
);
  import carfield_pkg::*;

  assign is_periphs_o =
    (addr_i >= PeriphsBase) &&
    (addr_i <  PeriphsEnd);

endmodule

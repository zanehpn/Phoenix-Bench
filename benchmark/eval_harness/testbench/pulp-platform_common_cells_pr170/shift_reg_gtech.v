/////////////////////////////////////////////////////////////
// Created by: Synopsys DC Ultra(TM) in wire load mode
// Version   : L-2016.03-SP1
// Date      : Sat Apr 11 18:58:11 2026
/////////////////////////////////////////////////////////////


module shift_reg ( clk_i, rst_ni, valid_i, d_i, valid_o, d_o );
  input clk_i, rst_ni, valid_i, d_i;
  output valid_o, d_o;


  DFFR_X1 valid_o_reg ( .D(valid_i), .CK(clk_i), .RN(rst_ni), .Q(valid_o) );
  DFFR_X1 d_o_reg ( .D(d_i), .CK(clk_i), .RN(rst_ni), .Q(d_o) );
endmodule


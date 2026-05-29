dc_shell -f dc_shift_reg_gtech.tcl > dc_shift_reg_gtech.log

if grep -q "The construct 'string' is not supported in synthesis" dc_shift_reg_gtech.log; then
  echo "FAIL:Synthesis encountered issues. Please check the log file."
else
  echo "PASS:Synthesis completed successfully."
fi

# Run SV testbench for patch-related functional coverage
vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  tb_carfield_string_param_patch.sv \
  -top tb_carfield_string_param_patch

./simv -cm line+cond+tgl+branch+fsm | tee simv.log
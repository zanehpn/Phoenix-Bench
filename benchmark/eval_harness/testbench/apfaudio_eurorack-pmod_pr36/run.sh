vcs -full64 -cm line+cond+tgl+branch+fsm -sverilog \
  ../../snapshots/apfaudio_eurorack-pmod_pr36/gateware/cores/util/wavetable_osc.sv \
  ../../snapshots/apfaudio_eurorack-pmod_pr36/gateware/cores/vco.sv \
  vco_tb_selfcheck.sv \
  -o simv

  ./simv -cm line+cond+tgl+branch+fsm | tee simv.log



remove_design -all

read_lib \
  NangateOpenCellLibrary_45nm/Low_Power/Front_End/Liberty/NLDM/LowPowerOpenCellLibrary_fast.lib

# report_lib NangateOpenCellLibrary_fast

write_lib \
  NangateOpenCellLibrary \
  -format db \
  -output NangateOpenCellLibrary_fast.db

quit

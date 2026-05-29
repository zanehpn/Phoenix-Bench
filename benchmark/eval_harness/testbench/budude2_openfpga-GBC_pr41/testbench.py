# check_audio_mapping.py
import re,sys
p = open("../../snapshots/budude2_openfpga-GBC_pr41/src/core/core_top.sv").read()
ok1 = re.search(r'\.core_l\s*\(\s*audio_l\s*\)', p)
ok2 = re.search(r'\.core_r\s*\(\s*audio_r\s*\)', p)
bad1 = re.search(r'\.core_l\s*\(\s*audio_r\s*\)', p)
bad2 = re.search(r'\.core_r\s*\(\s*audio_l\s*\)', p)
if ok1 and ok2 and not(bad1 or bad2):
    print("PASS: audio mapping correct")
    sys.exit(0)
else:
    print("FAIL: audio mapping incorrect")
    if not ok1: print(" - missing .core_l(audio_l)")
    if not ok2: print(" - missing .core_r(audio_r)")
    if bad1: print(" - found .core_l(audio_r)")
    if bad2: print(" - found .core_r(audio_l)")
    sys.exit(2)

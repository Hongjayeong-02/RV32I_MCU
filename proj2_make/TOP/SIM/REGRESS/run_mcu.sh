#!/bin/bash
# SoC-level regression (Xcelium) : tb_mcu + mcu_top
#   cd SIM/REGRESS ; bash run_mcu.sh          every program in PROG/
#                    bash run_mcu.sh quick    own tests t* and p* only
#   demo programs (PROG/d*) need the host-terminal TB : run_demo.sh
#                    bash run_mcu.sh [quick] chip   DUT = mcu_chip_top, PADs bypassed (M5)
#   hex mode    (PROG/<t>/expected.hex) : commit trace compared inside the TB
#   replay mode (peripheral tests p*)   : TOOLS/check_replay.py (python3)
#       no python3 on this server -> the trace / event files are compared by md5
#       with PROG/<t>/replay.md5, written on a machine where the replay PASSED
#       for this exact RTL : same bytes = same replay result (MD5OK).
#       MD5DIFF after an RTL change : copy log/mcu_<t>.{trace,ev} to a machine
#       with python3 and run TOOLS/check_replay.py there.
#   logs : log/mcu_<t>.{log,trace,ev,replay} ; table : sim_results_mcu.txt
cd "$(dirname "$0")" || exit 1
source ../sim_env.sh
mkdir -p log
QUICK=0; CHIPOPT=""
for a in "$@"; do
  [ "$a" = quick ] && QUICK=1
  # chip : DUT = mcu_chip_top with the PADs bypassed (M5) ; results must equal mcu_top's
  [ "$a" = chip ]  && CHIPOPT="-define CHIP -define NO_PAD $RTL/mcu_chip_top.v"
done
if [ $QUICK = 1 ]; then TESTS=$(ls $PROG | grep '^[tp]'); else TESTS=$(ls $PROG | grep -v '^d'); fi   # d* = demo programs : run_demo.sh
HAVE_PY=0; command -v python3 > /dev/null 2>&1 && HAVE_PY=1

for t in $TESTS; do
  n=mcu_$t
  echo "== RUN $n"
  hx=""; [ -f $PROG/$t/expected.hex ] && hx="+HEX=$PROG/$t/expected.hex"
  $XRUN $CHIPOPT $TB/tb_mcu.v $PROG/$t/rv32_rom.v $MCU_RTL -top tb_mcu +TEST=$t $hx \
     +TRACE=log/$n.trace +EVENTS=log/$n.ev -l log/$n.log > /dev/null 2>&1
  rm -f log/$n.replay
  if [ -z "$hx" ] && [ $HAVE_PY = 1 ]; then
    python3 $TOOLS/check_replay.py $PROG/$t/rom.bin log/$n.trace log/$n.ev --name $t > log/$n.replay 2>&1
  fi
done

{
  echo "# SoC RTL results (Xcelium) : hex = trace vs ISS in the TB, replay = TOOLS/check_replay.py"
  echo
  np=0; nf=0; ns=0
  for t in $TESTS; do
    n=mcu_$t ; f=log/$n.log
    if [ ! -f $f ]; then printf "%-28s log 없음\n" $n; nf=$((nf+1)); continue; fi
    p=$(grep -c "^PASS:" $f); q=$(grep -c "^FAIL" $f); e=$(grep -c '\*E,' $f)
    if [ -f $PROG/$t/expected.hex ]; then
      d=$(diff -q $PROG/$t/expected.trace log/$n.trace > /dev/null 2>&1 && echo same || echo DIFF); rp="-"
    else
      d="-"
      if [ $HAVE_PY = 1 ]; then rp=$(grep -q "ALL PASS" log/$n.replay 2>/dev/null && echo PASS || echo FAIL)
      else
        m1=$(md5sum < log/$n.trace | cut -d' ' -f1); m2=$(md5sum < log/$n.ev | cut -d' ' -f1)
        if [ -f $PROG/$t/replay.md5 ] && [ "$(sed -n 1p $PROG/$t/replay.md5 | cut -d' ' -f1)" = "$m1" ] && \
           [ "$(sed -n 2p $PROG/$t/replay.md5 | cut -d' ' -f1)" = "$m2" ]; then rp=MD5OK; else rp=MD5DIFF; ns=$((ns+1)); fi
      fi
    fi
    last=$(grep "ALL PASS\|FAIL " $f | tail -1 | sed 's/^MCU [^ ]* //' | cut -c1-80)
    if [ "$q" = 0 ] && [ "$e" = 0 ] && [ "$d" != DIFF ] && [ "$rp" != FAIL ] && [ "$rp" != MD5DIFF ] && grep -q "ALL PASS" $f; then np=$((np+1)); else nf=$((nf+1)); fi
    printf "%-26s PASS %2s FAIL %2s *E %2s trace %-4s replay %-7s | %s\n" $n $p $q $e $d $rp "$last"
  done
  echo
  echo "TOTAL : $np PASS, $nf FAIL   (replay needs re-check : $ns)"
} > sim_results_mcu.txt
echo
cat sim_results_mcu.txt

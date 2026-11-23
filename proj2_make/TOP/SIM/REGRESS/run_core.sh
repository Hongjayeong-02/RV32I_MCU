#!/bin/bash
# core program-level regression (Xcelium) : tb_rv32_core, commit trace vs ISS
#   cd SIM/REGRESS ; bash run_core.sh         every PROG/<t> with expected.hex, WAIT=0 and 1
#                    bash run_core.sh quick   own tests t* only
#   logs : log/core_<t>_w<0|1>.{log,trace} ; table : sim_results_core.txt
cd "$(dirname "$0")" || exit 1
source ../sim_env.sh
mkdir -p log
if [ "$1" = quick ]; then TESTS=$(ls $PROG | grep "^t"); else TESTS=$(cd $PROG && ls */expected.hex | cut -d/ -f1); fi

for t in $TESTS; do
  for w in 0 1; do
    n=core_${t}_w$w
    echo "== RUN $n"
    $XRUN $TB/tb_rv32_core.v $PROG/$t/rv32_rom.v $CORE_RTL -top tb_rv32_core \
       +HEX=$PROG/$t/expected.hex +TEST=$t +WAIT=$w +TRACE=log/$n.trace -l log/$n.log > /dev/null 2>&1
  done
done

{
  echo "# core program-level RTL results (Xcelium), commit trace vs ISS (TOOLS/rv32_iss.py)"
  echo "# w0 = no wait state, w1 = random 0-3 wait states on every data access"
  echo
  np=0; nf=0
  for t in $TESTS; do
    for w in 0 1; do
      n=core_${t}_w$w ; f=log/$n.log
      if [ ! -f $f ]; then printf "%-30s log 없음\n" $n; nf=$((nf+1)); continue; fi
      p=$(grep -c "^PASS:" $f); q=$(grep -c "^FAIL" $f); e=$(grep -c '\*E,' $f)
      d=$(diff -q $PROG/$t/expected.trace log/$n.trace > /dev/null 2>&1 && echo same || echo DIFF)
      last=$(grep "ALL PASS\|FAIL " $f | tail -1 | sed 's/^CORE [^ ]* //' | cut -c1-95)
      if [ "$q" = 0 ] && [ "$e" = 0 ] && [ "$d" = same ] && grep -q "ALL PASS" $f; then np=$((np+1)); else nf=$((nf+1)); fi
      printf "%-30s PASS %2s  FAIL %2s  *E %2s  trace %-4s | %s\n" $n $p $q $e $d "$last"
    done
  done
  echo
  echo "TOTAL : $np runs PASS, $nf runs FAIL"
} > sim_results_core.txt
echo
cat sim_results_core.txt

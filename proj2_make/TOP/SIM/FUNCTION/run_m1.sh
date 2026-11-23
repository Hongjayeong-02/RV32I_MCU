#!/bin/bash
# M1 leaf-module RTL regression (Xcelium)
#   cd SIM/FUNCTION ; bash run_m1.sh   -> log/*.log, sim_results.txt
cd "$(dirname "$0")" || exit 1
source ../sim_env.sh
mkdir -p log

run() {  # name top "rtl files" extra-args
  echo "== RUN $1"
  $XRUN $3 $TB/$2.v -top $2 $4 -l log/$1.log > /dev/null 2>&1
}

run alu      tb_rv32_alu      "$RTL/rv32_alu.v $RTL/rv32_branch.v"
run decoder  tb_rv32_decoder  "$RTL/rv32_decoder.v"
run imm_gen  tb_rv32_imm_gen  "$RTL/rv32_imm_gen.v"
run regfile  tb_rv32_regfile  "$RTL/rv32_regfile.v"
run ram_256B tb_rv32_ram      "$RTL/rv32_ram.v" "-defparam tb_rv32_ram.ADDR_W=6"
run ram_1KB  tb_rv32_ram      "$RTL/rv32_ram.v" "-defparam tb_rv32_ram.ADDR_W=8"
run ram_2KB  tb_rv32_ram      "$RTL/rv32_ram.v" "-defparam tb_rv32_ram.ADDR_W=9"

{
  echo "# M1 leaf-module RTL simulation results (Xcelium), from SIM/FUNCTION/log/*.log"
  echo
  for n in alu decoder imm_gen regfile ram_256B ram_1KB ram_2KB; do
    f=log/$n.log
    if [ ! -f $f ]; then printf "%-10s  log 없음\n" $n; continue; fi
    p=$(grep -c "^PASS:" $f); q=$(grep -c "^FAIL" $f); e=$(grep -c '\*E,' $f)
    last=$(grep "ALL PASS\|FAIL " $f | tail -1 | cut -c1-50)
    printf "%-10s  PASS %4s  FAIL %3s  *E %2s  | %s\n" $n $p $q $e "$last"
  done
} > sim_results.txt
echo
cat sim_results.txt

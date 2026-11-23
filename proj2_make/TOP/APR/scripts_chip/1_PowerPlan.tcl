########################################
# PowerPlan : mcu_chip_top (core ring + stripes, power PADs -> ring)
########################################

# restoreDesign InitDesign.dat mcu_chip_top

## Global Net Connect (Tie)
globalNetConnect VDD -type tiehi -inst * -override
globalNetConnect VSS -type tielo -inst * -override

## Core Ring (in the 30 um channel between the PAD ring and the core)
addRing -nets {VDD VSS} -type core_rings -follow core \
        -layer   {top Metal9 bottom Metal9 left Metal8 right Metal8} \
        -width   {top 2 bottom 2 left 2 right 2} \
        -spacing {top 1 bottom 1 left 1 right 1} \
        -offset  {top 1 bottom 1 left 1 right 1} \
        -center 1

## Stripe (core ~460 um : every 30 um)
addStripe -nets {VDD VSS} -layer Metal8 -direction vertical \
          -width 1 -spacing 1 -set_to_set_distance 30 \
          -start_from left -start_offset 15

## Special Route (cell rail -> ring / stripe, power PAD pin -> ring)
sroute -connect {corePin padPin} -nets {VDD VSS} \
       -allowJogging 1 -allowLayerChange 1 \
       -layerChangeRange {Metal1 Metal9} \
       -corePinTarget {ring stripe} -padPinTarget {ring}

## Verify
verifyConnectivity -type special -error 1000 -warning 50 -report mcu_chip_top.powerConn.rpt
verify_drc -limit 1000 -report mcu_chip_top.powerDrc.rpt

saveDesign PowerPlan

########################################
# Placement + preCTS Opt : mcu_top
########################################

# restoreDesign PowerPlan.dat mcu_top

setDesignMode -process 45

## Dont Use : CoreSiteDouble cells (floorplan row is CoreSite only)
foreach c [dbGet [dbGet head.libCells.site.name CoreSiteDouble -p2].name] {
    setDontUse $c true
}

## Placement
placeDesign

## Tie Cell
setTieHiLoMode -cell {TIEHI TIELO} -maxFanout 8
addTieHiLo

## preCTS Opt
optDesign -preCTS -outDir reports/preCTS_opt

## Verify
checkPlace mcu_top.checkPlace.rpt
timeDesign -preCTS -outDir reports/preCTS -prefix preCTS
report_area > reports/preCTS_area.rpt

## Save Design
saveDesign PlaceOpt

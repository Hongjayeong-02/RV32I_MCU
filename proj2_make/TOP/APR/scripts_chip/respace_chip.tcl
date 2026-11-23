########################################
# respace_chip.tcl : spread the PADs of every side with INTEGER um gaps
#   (UART V3 respace.tcl, generalised to 4 sides) so that the 1 um IO fillers fill
#   every gap and the IO-ring rails stay continuous.
########################################
set dieW [lindex [dbGet top.fPlan.box] 0 2]
set dieH [lindex [dbGet top.fPlan.box] 0 3]
# corner size from a corner cell
set cb [lindex [dbGet [dbGet top.insts.cell.name padIORINGCORNER -p2].box] 0]
set CS [expr {[lindex $cb 2] - [lindex $cb 0]}]
puts "RESPACE die $dieW x $dieH corner $CS"

foreach side {L R B T} {
  set lst {}
  foreach i [dbGet top.insts] {
    set cn [dbGet $i.cell.name]
    if {![string match -nocase pad* $cn] || [string match -nocase *CORNER* $cn] || [string match -nocase *FEED* $cn]} continue
    set b  [lindex [dbGet $i.box] 0]
    set cx [expr {([lindex $b 0] + [lindex $b 2]) / 2.0}]
    set cy [expr {([lindex $b 1] + [lindex $b 3]) / 2.0}]
    # nearest die edge = side
    set d [list [list L $cx] [list R [expr {$dieW - $cx}]] [list B $cy] [list T [expr {$dieH - $cy}]]]
    set s [lindex [lsort -real -index 1 $d] 0 0]
    if {$s ne $side} continue
    if {$side eq "L" || $side eq "R"} {
      lappend lst [list [lindex $b 1] $i [expr {[lindex $b 3] - [lindex $b 1]}]]
    } else {
      lappend lst [list [lindex $b 0] $i [expr {[lindex $b 2] - [lindex $b 0]}]]
    }
  }
  set lst  [lsort -real -index 0 $lst]
  set n    [llength $lst]
  if {$n == 0} continue
  set L    [expr {($side eq "L" || $side eq "R") ? $dieH : $dieW}]
  set used 0.0
  foreach e $lst { set used [expr {$used + [lindex $e 2]}] }
  set spare [expr {int(floor($L - 2 * $CS - $used))}]
  set base  [expr {$spare / ($n + 1)}]
  set extra [expr {$spare % ($n + 1)}]
  set p $CS
  set k 0
  foreach e $lst {
    set g $base
    if {$k < $extra} { incr g }
    set p [expr {$p + $g}]
    set i [lindex $e 1]
    if {$side eq "L" || $side eq "R"} {
      dbSet $i.pt_y [expr {[dbGet $i.pt_y] + $p - [lindex $e 0]}]
    } else {
      dbSet $i.pt_x [expr {[dbGet $i.pt_x] + $p - [lindex $e 0]}]
    }
    set p [expr {$p + [lindex $e 2]}]
    incr k
  }
  puts "RESPACE $side n=$n spare=$spare base=$base extra=$extra last_end=$p"
}

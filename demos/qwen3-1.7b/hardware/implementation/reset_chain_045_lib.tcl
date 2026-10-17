# Pure validation procedures shared by the read-only observer and local tests.
# No Vivado command, exception, design write, or clock modification occurs here.
proc reset045_require {condition message} {
    if {!$condition} {error $message}
}
proc reset045_validate {stem depth clock stages} {
    reset045_require [expr {$depth >= 2 && $depth <= 10}] "Unsupported reset-chain depth"
    reset045_require [expr {[llength $stages] == $depth}] "Wrong stage count: $stem"
    set common_clear ""
    for {set i 0} {$i < $depth} {incr i} {
        set row [lindex $stages $i]
        set cell [format {%s_reg[%d]} $stem $i]
        foreach key {cell primitive async clock clock_net clear_driver clear_net ce_driver ce_primitive d_driver d_primitive loads} {
            reset045_require [dict exists $row $key] "Missing stage observation $key"
        }
        reset045_require [expr {[dict get $row cell] eq $cell}] "Wrong stage identity"
        reset045_require [expr {[dict get $row primitive] eq "FDCE" && [dict get $row async] in {1 TRUE}}] "Not an asynchronous FDCE chain"
        reset045_require [expr {[dict get $row clock] eq $clock && [dict get $row clock_net] ne ""}] "Wrong stage clock"
        set clear [list [dict get $row clear_driver] [dict get $row clear_net]]
        if {$i == 0} {set common_clear $clear; set common_clock [dict get $row clock_net]}
        reset045_require [expr {$clear eq $common_clear && [lindex $clear 0] ne "" && [lindex $clear 1] ne ""}] "Mixed/empty asynchronous clear"
        reset045_require [expr {[dict get $row clock_net] eq $common_clock}] "Mixed clock nets"
        reset045_require [expr {[dict get $row ce_primitive] eq "VCC" && [dict get $row ce_driver] ne ""}] "Conditional clock enable"
        if {$i == 0} {
            reset045_require [expr {[dict get $row d_primitive] eq "VCC" && [dict get $row d_driver] ne ""}] "First D is not constant one"
        } else {
            reset045_require [expr {[dict get $row d_driver] eq [format {%s_reg[%d]/Q} $stem [expr {$i-1}]] && [dict get $row d_primitive] eq "FDCE"}] "Broken direct D chain"
        }
        if {$i+1 < $depth} {
            reset045_require [expr {[dict get $row loads] eq [list [format {%s_reg[%d]/D} $stem [expr {$i+1}]]]}] "Intermediate-stage fanout"
        }
    }
    return $common_clear
}
proc reset045_family {stem depth cells} {
    set expected [list]
    for {set i 0} {$i < $depth} {incr i} {lappend expected [format {%s_reg[%d]} $stem $i]}
    reset045_require [expr {[lsort $cells] eq [lsort $expected]}] "Changed family, replica, missing stage, or depth: $stem"
}

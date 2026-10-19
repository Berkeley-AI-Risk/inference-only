# Revalidate the working design's reset-release contract on a fresh netlist.
# Merely sourcing this file changes no design or constraint. Collection fails
# closed if a family, primitive, fanout, constant input or clock has changed.
# Only pcr_apply explicitly installs the 154 validated raw-CLR exceptions.
# Functional resets and all synchronizer interstage paths remain timed.
proc pcr_sha {path} {return [lindex [exec sha256sum $path] 0]}
proc pcr_one {objects label} {
    if {[llength $objects] != 1} {error "Expected one $label: $objects"}
    return [lindex $objects 0]
}
proc pcr_names {objects} {
    if {![llength $objects]} {return {}}
    return [lsort -unique [get_property NAME $objects]]
}
proc pcr_pin {cell leaf} {
    return [pcr_one [get_pins -quiet -of_objects $cell -filter "REF_PIN_NAME == $leaf"] "$cell/$leaf"]
}
proc pcr_nets {pin} {return [get_nets -quiet -segments -of_objects $pin]}
proc pcr_driver {pin} {
    set driver [pcr_one [get_pins -quiet -leaf -of_objects [pcr_nets $pin] -filter {DIRECTION == OUT}] "driver of $pin"]
    set cell [pcr_one [get_cells -of_objects $driver] "driver cell of $pin"]
    return [list [get_property NAME $driver] [get_property REF_NAME $cell]]
}
proc pcr_row {cell} {
    lassign [pcr_driver [pcr_pin $cell D]] dd dr
    lassign [pcr_driver [pcr_pin $cell CE]] ce cr
    lassign [pcr_driver [pcr_pin $cell CLR]] cl cp
    return [dict create cell [get_property NAME $cell] primitive [get_property REF_NAME $cell] \
        async [get_property ASYNC_REG $cell] \
        clock [get_property NAME [pcr_one [get_clocks -of_objects [pcr_pin $cell C]] "release-chain clock"]] \
        clock_net [pcr_names [pcr_nets [pcr_pin $cell C]]] clear_driver $cl \
        clear_net [pcr_names [pcr_nets [pcr_pin $cell CLR]]] \
        ce_driver $ce ce_primitive $cr d_driver $dd d_primitive $dr \
        loads [pcr_names [get_pins -quiet -leaf -of_objects [pcr_nets [pcr_pin $cell Q]] -filter {DIRECTION == IN}]]]
}
proc pcr_allowlist {text prefix} {
    if {$prefix ni {{} WRAPPER/CL/}} {error "Unexpected reset scope prefix"}
    set lines [split [string trimright $text "\n"] "\n"]
    if {[llength $lines] != 139 || [lindex $lines 0] ne "stem\tstages\tconstant_one_reset_shift_structure\treasons\tclock\tclear_net"} {
        error "Changed reset-family inventory format"
    }
    set result {}
    foreach line [lrange $lines 1 end] {
        if {[llength [split $line "\t"]] != 6} {error "Bad reset-family row"}
        lassign [split $line "\t"] stem depth eligible reasons clock clear
        if {$eligible eq "1"} {
            if {$reasons ne "" || $clear eq "" || ![regexp {^fixed_(machine|hbm_reset)/} $stem]} {
                error "Unreviewed reset family"
            }
            lappend result [list $prefix$stem $depth $clock]
        }
    }
    if {[llength $result] != 48 || [llength [lsort -unique $result]] != 48} {error "Wrong reset-family set"}
    return $result
}
proc pcr_collect {inventory library output prefix} {
    if {[pcr_sha $inventory] ne "bb17813e84391ab1d4c04496bd0956bae4629a493acb2af8826e13d03a7789c5" ||
        [pcr_sha $library] ne "cb7a6cfca01341a86ce13a9b67d503ba8af49b403ba6c26b07070201c3f30763"} {
        error "Reset contract provenance changed"
    }
    source $library
    set stream [open $inventory r];set text [read $stream];close $stream
    set allowlist [pcr_allowlist $text $prefix]
    set cells {}
    foreach cell [get_cells -quiet -hier -filter {IS_SEQUENTIAL == 1}] {
        dict set cells [get_property NAME $cell] $cell
    }
    set report [open $output/reset-stages.tsv {WRONLY CREAT EXCL}]
    puts $report "stem\tstage\tobservations"
    set selected {}
    foreach item $allowlist {
        lassign $item stem depth clock
        set family {}
        dict for {name cell} $cells {
            if {[string first "${stem}_reg" $name] == 0} {lappend family $name}
        }
        reset045_family $stem $depth $family
        set rows {}
        for {set i 0} {$i < $depth} {incr i} {
            set cell [dict get $cells [format {%s_reg[%d]} $stem $i]]
            set observed [pcr_row $cell]
            lappend rows $observed
            lappend selected [pcr_pin $cell CLR]
            puts $report [join [list $stem $i $observed] "\t"]
        }
        reset045_validate $stem $depth $clock $rows
    }
    close $report
    if {[llength $selected] != 154 || [llength [pcr_names $selected]] != 154} {error "Wrong exact raw-CLR set"}
    set report [open $output/reset-input-pins.txt {WRONLY CREAT EXCL}]
    puts $report [join [pcr_names $selected] "\n"];close $report
    puts "PARALLEL_RESET_STRUCTURE_PASSED chains=48 raw_CLR_pins=154 prefix=$prefix"
    return [dict create selected $selected cells $cells allowlist $allowlist prefix $prefix]
}
proc pcr_apply {contract} {
    set selected [dict get $contract selected]
    if {[llength $selected] != 154} {error "Unvalidated reset contract"}
    set_false_path -to $selected
    puts "PARALLEL_RESET_CONTRACT_APPLIED raw_CLR_pins=154 ordinary_resets_excluded=0"
}
proc pcr_retained_timing {contract output require_met} {
    set cells [dict get $contract cells];set prefix [dict get $contract prefix]
    set checks {}
    foreach item [dict get $contract allowlist] {
        lassign $item stem depth clock
        for {set i 0} {$i+1 < $depth} {incr i} {
            # Register C is a timing startpoint; Q would segment the C->Q arc.
            set from [pcr_pin [dict get $cells [format {%s_reg[%d]} $stem $i]] C]
            set to [pcr_pin [dict get $cells [format {%s_reg[%d]} $stem [expr {$i+1}]]] D]
            lappend checks [list interstage $from $to]
        }
    }
    if {[llength $checks] != 106} {error "Incomplete interstage coverage"}
    set from [pcr_pin [dict get $cells "${prefix}fixed_machine/lifecycle/flr_shell_release_reg\[2\]"] C]
    foreach {stem depth} {core_ack_sync 3 memory_ack_sync 3 flr_timer 7 flr_done 1} {
        for {set i 0} {$i < $depth} {incr i} {
            set leaf [expr {$stem eq "flr_done" ? "flr_done_reg" : [format {%s_reg[%d]} $stem $i]}]
            set to [pcr_pin [dict get $cells "${prefix}fixed_machine/lifecycle/$leaf"] CLR]
            if {[lsearch -exact [dict get $contract selected] $to] >= 0} {error "Functional reset was excluded"}
            lappend checks [list functional_flr $from $to]
        }
    }
    if {[llength $checks] != 120} {error "Incomplete functional-reset coverage"}
    set report [open $output/reset-retained-timing.tsv {WRONLY CREAT EXCL}]
    puts $report "kind\tfrom\tto\tdelay\tslack_ns"
    foreach check $checks {
        lassign $check kind from to
        foreach delay {max min} {
            set path [pcr_one [get_timing_paths -quiet -from $from -to $to -delay_type $delay -max_paths 1] "$kind $delay path"]
            set slack [get_property SLACK $path]
            if {![string is double -strict $slack] || !($slack > -1e9 && $slack < 1e9)} {error "Nonfinite reset timing"}
            puts $report [join [list $kind $from $to $delay $slack] "\t"]
            if {$require_met && $slack < 0} {error "Failing retained reset path: $from $to $delay $slack"}
        }
    }
    close $report
    puts "PARALLEL_RESET_RETAINED_TIMING_CHECKED interstage_paths=212 functional_flr_paths=28 require_met=$require_met"
}

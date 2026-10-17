# Candidate constraints, to be checked against a real Vivado netlist/reports.
# Do NOT add broad asynchronous clock groups or clock-to-clock false paths:
# those would override the Gray-bus max-delay constraints below.
proc qwen_one {objects description} {
    if {[llength $objects] != 1} {error "Expected one $description, got: $objects"}
    return [lindex $objects 0]
}
proc qwen_pin {cell name} {
    return [qwen_one [get_pins -quiet -of_objects $cell -filter "REF_PIN_NAME == $name"] "$name pin on $cell"]
}
proc qwen_period {cell} {
    set clock [qwen_one [get_clocks -quiet -of_objects [qwen_pin $cell C]] "clock on $cell"]
    set period [get_property PERIOD $clock]
    if {![string is double -strict $period] || $period <= 0} {error "Invalid clock period: $clock"}
    return $period
}
proc qwen_apply_cdc_constraints {} {
    set fifos [get_cells -quiet -hier -filter {REF_NAME =~ qwen_async_stream_fifo*}]
    if {[llength $fifos] == 0} {error "No private asynchronous FIFOs found; cannot apply CDC constraints"}
    # Map exact names once. Tcl dict keys safely preserve generate-index brackets.
    set pointers [get_cells -quiet -hier -regexp {.*(read_gray|write_gray|read_gray_source_[123]|write_gray_destination_[123])_reg\[[0-9]+\]}]
    set cells [dict create]
    foreach cell $pointers {dict set cells [get_property NAME $cell] $cell}
    set buses 0
    set bits 0
    foreach fifo $fifos {
        set prefix "[get_property NAME $fifo]/"
        foreach {source_name target_name} {read_gray read_gray_source write_gray write_gray_destination} {
            set from_pins [list]
            set to_pins [list]
            set bit 0
            set bound 1e6
            while {[dict exists $cells [format {%s%s_reg[%d]} $prefix $source_name $bit]]} {
                set source [dict get $cells [format {%s%s_reg[%d]} $prefix $source_name $bit]]
                for {set stage 1} {$stage <= 3} {incr stage} {
                    set name [format {%s%s_%d_reg[%d]} $prefix $target_name $stage $bit]
                    if {![dict exists $cells $name]} {error "Missing pointer synchronizer: $name"}
                    set target [dict get $cells $name]
                    if {![get_property ASYNC_REG $target]} {error "Pointer synchronizer lost ASYNC_REG: $name"}
                    if {$stage == 1} {
                        lappend to_pins [qwen_pin $target D]
                        set bound [expr {min($bound, [qwen_period $target])}]
                    }
                }
                # A register's C pin is the valid timing startpoint. Using Q
                # segments its C->Q timing arc (Vivado Constraints 18-515).
                # -datapath_only already removes clock skew without doing that.
                lappend from_pins [qwen_pin $source C]
                set bound [expr {min($bound, [qwen_period $source])}]
                incr bit
            }
            if {$bit < 2} {error "Missing or renamed Gray bus $prefix$source_name"}
            # Check no tail bits were silently skipped after a numbering gap.
            set count 0
            dict for {name cell} $cells {
                if {[string first "${prefix}${source_name}_reg\[" $name] == 0} {incr count}
            }
            if {$count != $bit} {error "Noncontiguous Gray bus $prefix$source_name"}
            set_max_delay -datapath_only $bound -from $from_pins -to $to_pins
            set_bus_skew $bound -from $from_pins -to $to_pins
            puts "QWEN_CDC_GRAY $prefix$source_name bits=$bit bound_ns=$bound"
            incr buses
            incr bits $bit
        }
    }
    # Only explicitly named first stages get data-path exceptions. Later
    # synchronizer stages, payload RAM paths and reset recovery/removal remain
    # timed. Vendor XPM constraints remain the vendor IP's responsibility.
    set status_names {ready_sync loading_sync error_sync ready_to_shell error_to_shell
        ingress_error_to_core memory_error_core core_reset_sync memory_reset_sync
        reference_reset_sync monitor0_sync monitor1_sync memory_release_sync
        core_ack_sync memory_ack_sync reference_start memory_start reference_done_sync
        memory_done_sync axi_settle_sync flr_reference_start flr_memory_start
        flr_reference_sync flr_memory_sync axi_reset_state_sync}
    set status_count 0
    foreach cell [get_cells -quiet -hier -filter {ASYNC_REG == TRUE}] {
        set name [get_property NAME $cell]
        if {[regexp {(^|/)([^/]+)_reg\[0\]$} $name unused parent leaf]
                && [lsearch -exact $status_names $leaf] >= 0} {
            set_false_path -to [qwen_pin $cell D]
            incr status_count
        }
    }
    if {$status_count == 0} {error "No named first-stage status synchronizers found"}
    puts "QWEN_CDC_COVERAGE fifo_instances=[llength $fifos] gray_buses=$buses gray_bits=$bits status_first_stages=$status_count"
}

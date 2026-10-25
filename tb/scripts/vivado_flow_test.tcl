# Pure Tcl contract tests. All Vivado commands are mocked; no FPGA tools run.
set repo_root [file normalize [file join [file dirname [info script]] "../.."]]
set script_root [file join $repo_root "vivado/scripts"]
set calls [list]
proc check {condition message} {
    if {!$condition} { error $message }
}
proc mock_parts {boards args} {
    check [expr {$args eq {-quiet *ultra96*}}] "unexpected board query"
    return $boards
}
proc record {name args} {
    global calls
    lappend calls [linsert $args 0 $name]
    if {$name eq "get_ports"} { return [lindex $args 0] }
    return ""
}
proc probe {entry boards expected_exit {board_repo ""}} {
    global script_root calls
    set calls [list]
    set slave [interp create]
    interp alias $slave get_board_parts {} mock_parts $boards
    interp alias $slave set_param {} record set_param
    interp eval $slave {
        proc puts {args} {}
        proc exit {{code 0}} { return -code error -errorcode [list TEST_EXIT $code] "probe stopped" }
        unset -nocomplain ::env(ULTRA96_BOARD_REPO)
    }
    if {$board_repo ne ""} { interp eval $slave [list set ::env(ULTRA96_BOARD_REPO) $board_repo] }
    set caught [catch {interp eval $slave [list source [file join $script_root $entry]]} message options]
    check $caught "probe did not terminate explicitly"
    check [expr {[dict get $options -errorcode] eq [list TEST_EXIT $expected_exit]}] \
        "unexpected probe result: $message"
    if {$board_repo ne ""} {
        check [expr {[lindex $calls 0] eq [list set_param board.repoPaths [list [file normalize $board_repo]]]}] \
            "board repository override was not applied"
    }
    interp delete $slave
}
set v1 "em.avnet.com:ultra96v1:part0:1.2"
set v2 "em.avnet.com:ultra96v2:part0:1.2"
set legacy "avnet.com:ultra96:part0:1.0"
probe check_ultra96_v2_board.tcl {} 1
probe check_ultra96_v2_board.tcl [list $v1] 1
probe check_ultra96_v2_board.tcl [list $v2] 0
probe check_ultra96_v2_board.tcl [list $v1 $v2] 0
probe check_ultra96_v2_board.tcl [list $v2] 0 $script_root
probe check_ultra96_v1_board.tcl [list $v1] 0
probe check_ultra96_v1_board.tcl [list $legacy] 0
probe check_ultra96_v1_board.tcl [list $v2] 1

# Parse/execute the optional sweep's orchestration, without synthesizing RTL or
# writing reports/checkpoints/directories. Constraint Tcl is parsed as well.
proc mock_file {subcommand args} {
    if {$subcommand eq "mkdir"} { return "" }
    if {$subcommand in {delete copy rename tempfile}} { error "unexpected filesystem mutation" }
    return [file $subcommand {*}$args]
}
set calls [list]
set slave [interp create]
interp alias $slave file {} mock_file
foreach command {create_project read_verilog synth_design report_utilization report_timing_summary write_checkpoint close_project create_clock get_ports} {
    interp alias $slave $command {} record $command
}
interp eval $slave {
    proc puts {args} {}
    proc read_xdc {path} { source $path }
}
interp eval $slave [list source [file join $script_root "run_ultra96_v2_parallelism_sweep.tcl"]]
set filters [list]
set clocks 0
foreach call $calls {
    if {[lindex $call 0] eq "synth_design"} {
        set generic_index [lsearch -exact $call -generic]
        lappend filters [lindex $call [expr {$generic_index + 1}]]
        check [expr {[lindex $call [expr {[lsearch -exact $call -part] + 1}]] eq "xczu3eg-sbva484-1-i"}] \
            "sweep lost the V2 industrial device selection"
    }
    if {[lindex $call 0] eq "create_clock"} {
        incr clocks
        check [expr {$call eq {create_clock -name aclk -period 10.000 aclk}}] "wrong sweep clock constraint"
    }
}
check [expr {$filters eq {PARALLEL_FILTERS=1 PARALLEL_FILTERS=2 PARALLEL_FILTERS=4}}] "wrong filter configurations"
check [expr {$clocks == 3}] "clock constraint not applied to every sweep case"
interp delete $slave
puts "PASS: 8 board probes and 3 mocked sweep configurations; no Vivado/synthesis execution"

# Shared board probe. V2 callers set the variant before sourcing this file.
# No project, synthesis or implementation is launched by this check.
if {![info exists ultra96_board_variant]} { set ultra96_board_variant "v1" }
if {![info exists ultra96_board_label]} { set ultra96_board_label "Ultra96-V1" }
if {$ultra96_board_variant ni {v1 v2}} { error "Unsupported Ultra96 board variant" }

if {[info exists ::env(ULTRA96_BOARD_REPO)] && $::env(ULTRA96_BOARD_REPO) ne ""} {
    if {![file isdirectory $::env(ULTRA96_BOARD_REPO)]} {
        error "ULTRA96_BOARD_REPO must name an existing board-store directory."
    }
    set_param board.repoPaths [list [file normalize $::env(ULTRA96_BOARD_REPO)]]
}

set matches [get_board_parts -quiet *ultra96*]
puts "\nUltra96 board parts visible to Vivado:"
if {[llength $matches] == 0} {
    puts "  NONE"
    puts "Install the Avnet $ultra96_board_label definition from Tools > Vivado Store > Boards."
    exit 1
}
set candidates [list]
foreach match $matches {
    puts "  $match"
    set name [string tolower $match]
    if {$ultra96_board_variant eq "v2"} {
        if {[string match "*ultra96v2*" $name]} { lappend candidates $match }
    } elseif {[string match "*ultra96v1*" $name] ||
              ([string match "*ultra96:*" $name] && ![string match "*ultra96v2*" $name])} {
        lappend candidates $match
    }
}
if {[llength $candidates] == 0} {
    puts "ERROR: Ultra96 definitions exist, but none target $ultra96_board_label."
    exit 1
}
puts "\n$ultra96_board_label candidate: [lindex $candidates end]"
exit 0

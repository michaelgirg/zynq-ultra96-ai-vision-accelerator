# Create the Ultra96-V2 heterogeneous ARM + RV32IM vision-control SoC.

set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir "../.."]]

set project_name "u96v2_rv32_soc"
set project_dir [file normalize [file join $repo_root "vivado/u96v2_rv32_soc_vivado"]]
set bd_name "u96v2rv32"
set part_name "xczu3eg-sbva484-1-i"
set ultra96_board_variant "v2"
set ultra96_board_label "Ultra96-V2"
set ultra96_board_check_script "check_ultra96_v2_board.tcl"
set ultra96_board_preferred [list \
    "em.avnet.com:ultra96v2:part0:1.2" \
    "avnet.com:ultra96v2:part0:1.2" \
    "em.avnet.com:ultra96v2:part0:1.1" \
    "avnet.com:ultra96v2:part0:1.1" \
    "em.avnet.com:ultra96v2:part0:1.0" \
    "avnet.com:ultra96v2:part0:1.0" \
]
set enable_rv32_soc 1

source [file join $script_dir "create_ultra96_v1_production_v2_project.tcl"]

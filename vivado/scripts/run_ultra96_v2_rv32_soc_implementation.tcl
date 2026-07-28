set script_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $script_dir "../.."]]
set project_path [file normalize [file join $repo_root "vivado/u96v2_rv32_soc_vivado/u96v2_rv32_soc.xpr"]]
set report_dir [file normalize [file join $repo_root "hardware/reports/ultra96_v2/rv32_soc/impl"]]
set xsa_path [file normalize [file join $repo_root "vivado/ultra96_v2_rv32_ai_vision_soc.xsa"]]
set ultra96_board_label "Ultra96-V2 RV32 control SoC"
set additional_ip_repos [list \
    [file normalize [file join $repo_root "vivado/ip_repo_rv32_soc"]] \
]

source [file join $script_dir "run_ultra96_v1_production_v2_implementation.tcl"]

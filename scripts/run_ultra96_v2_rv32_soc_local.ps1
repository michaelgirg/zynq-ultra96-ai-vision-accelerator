param(
    [string]$VivadoPath = "vivado",
    [string]$BoardRepo = "",
    [ValidateSet("package", "create", "synth", "impl", "all")]
    [string]$Stage = "all"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $projectRoot "vivado\scripts"
$logRoot = Join-Path $projectRoot "hardware\reports\ultra96_v2\rv32_soc\logs"
New-Item -ItemType Directory -Force -Path $logRoot | Out-Null

if ([System.IO.Path]::IsPathRooted($VivadoPath)) {
    if (-not (Test-Path -LiteralPath $VivadoPath)) {
        throw "Vivado was not found at $VivadoPath"
    }
}
elseif (-not (Get-Command $VivadoPath -ErrorAction SilentlyContinue)) {
    throw "Vivado command '$VivadoPath' is not on PATH; pass -VivadoPath with the full path to vivado.bat."
}

if (-not $BoardRepo) {
    $vivadoSettingsRoot = Join-Path $env:APPDATA "Xilinx\Vivado"
    if (Test-Path -LiteralPath $vivadoSettingsRoot) {
        $settingsVersions = Get-ChildItem -LiteralPath $vivadoSettingsRoot -Directory |
            Where-Object { $_.Name -match '^\d+\.\d+$' } |
            Sort-Object Name -Descending
        foreach ($settingsVersion in $settingsVersions) {
            $candidate = Join-Path $settingsVersion.FullName (
                "xhub\board_store\xilinx_board_store\XilinxBoardStore\Vivado\" +
                $settingsVersion.Name + "\boards"
            )
            if (Test-Path -LiteralPath (Join-Path $candidate "Avnet\ultra96v2")) {
                $BoardRepo = $candidate
                break
            }
        }
    }
}
if ($BoardRepo) {
    $env:ULTRA96_BOARD_REPO = (Resolve-Path -LiteralPath $BoardRepo).Path
    Write-Host "Using board repository: $env:ULTRA96_BOARD_REPO"
}

function Invoke-VivadoStage {
    param([string]$ScriptName)
    $scriptPath = Join-Path $scriptRoot $ScriptName
    $logPath = Join-Path $logRoot ($ScriptName -replace '\.tcl$', '.log')
    & $VivadoPath -mode batch -source $scriptPath -log $logPath -journal ($logPath -replace '\.log$', '.jou')
    if ($LASTEXITCODE -ne 0) {
        throw "Vivado stage failed: $ScriptName (exit $LASTEXITCODE)"
    }
}

function Invoke-Rv32IpPackaging {
    Invoke-VivadoStage "package_axis_preprocess_vector_cdc_ip_ultra96.tcl"
    Invoke-VivadoStage "package_rv32_control_soc_ip.tcl"
}

switch ($Stage) {
    "package" { Invoke-Rv32IpPackaging }
    "create"  { Invoke-VivadoStage "create_ultra96_v2_rv32_soc_project.tcl" }
    "synth"   { Invoke-VivadoStage "run_ultra96_v2_rv32_soc_synth.tcl" }
    "impl"    { Invoke-VivadoStage "run_ultra96_v2_rv32_soc_implementation.tcl" }
    "all" {
        Invoke-VivadoStage "check_ultra96_v2_board.tcl"
        Invoke-Rv32IpPackaging
        Invoke-VivadoStage "create_ultra96_v2_rv32_soc_project.tcl"
        Invoke-VivadoStage "run_ultra96_v2_rv32_soc_synth.tcl"
        Invoke-VivadoStage "run_ultra96_v2_rv32_soc_implementation.tcl"
    }
}

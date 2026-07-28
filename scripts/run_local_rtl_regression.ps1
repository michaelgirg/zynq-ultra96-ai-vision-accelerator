param(
    [string]$QuestaBin = "",
    [string]$PythonExe = "python",
    [switch]$KeepSimulatorOutputs
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot

function Resolve-QuestaTool {
    param([string]$Name)

    if ($QuestaBin) {
        $candidate = Join-Path $QuestaBin "$Name.exe"
        if (-not (Test-Path -LiteralPath $candidate)) {
            throw "Missing Questa executable: $candidate"
        }
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Cannot find $Name on PATH; pass -QuestaBin with the Questa executable directory."
    }
    return $command.Source
}

$vlib = Resolve-QuestaTool "vlib"
$vlog = Resolve-QuestaTool "vlog"
$vsim = Resolve-QuestaTool "vsim"

function Invoke-CheckedCommand {
    param(
        [string]$Executable,
        [string[]]$Arguments
    )
    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Executable failed with exit code $LASTEXITCODE"
    }
}

function Invoke-DirectedTest {
    param(
        [string]$Top,
        [string[]]$ExtraArguments,
        [string]$PassMarker,
        [string]$LogName
    )
    $logPath = Join-Path $projectRoot $LogName
    $arguments = @(
        "-c",
        "-voptargs=+acc",
        $Top
    ) + $ExtraArguments + @(
        "-l",
        $logPath,
        "-do",
        "run -all; quit -f"
    )
    Invoke-CheckedCommand -Executable $vsim -Arguments $arguments
    $logText = Get-Content -LiteralPath $logPath -Raw
    if (($logText -notmatch [regex]::Escape($PassMarker)) -or
        ($logText -notmatch "Errors:\s+0")) {
        throw "Directed test $Top failed; inspect $logPath"
    }
}

$temporaryLogs = @()
Push-Location $projectRoot
try {
    if (Test-Path -LiteralPath "work") {
        Remove-Item -LiteralPath "work" -Recurse -Force
    }
    Invoke-CheckedCommand -Executable $vlib -Arguments @("work")
    Invoke-CheckedCommand -Executable $vlog -Arguments @("-sv", "-f", "tb/filelist.f")

    $temporaryLogs += "local_scalar_top.log"
    $testArguments = @{
        Top = "axis_preprocess_axi_lite_tb"
        ExtraArguments = @("+MODE=0")
        PassMarker = "PASS: AXI4-Stream selectable top mode 0 matched 784 pixels"
        LogName = "local_scalar_top.log"
    }
    Invoke-DirectedTest @testArguments

    foreach ($mode in 0..3) {
        $logName = "local_mode_${mode}.log"
        $temporaryLogs += $logName
        $testArguments = @{
            Top = "axis_preprocess_vector_axi_lite_tb"
            ExtraArguments = @("+MODE=$mode")
            PassMarker = "PASS: AXI4-Stream selectable top mode $mode matched 2 frames x 784 pixels"
            LogName = $logName
        }
        Invoke-DirectedTest @testArguments
    }

    foreach ($lanes in @(1, 2, 4)) {
        $logName = "local_lanes_${lanes}.log"
        $temporaryLogs += $logName
        $testArguments = @{
            Top = "axis_conv3x3_scalable_preprocess_tb"
            ExtraArguments = @("-gPARALLEL_FILTERS=$lanes")
            PassMarker = "PASS: scalable convolution lanes=$lanes matched 784 outputs"
            LogName = $logName
        }
        Invoke-DirectedTest @testArguments
    }

    foreach ($axisHalfPeriod in @(1850, 3500, 6500)) {
        # Use a fresh optimized library per generic variant. Questa Starter
        # 2021.2 can corrupt its incremental vopt cache after several
        # assertion-heavy parameterized elaborations.
        if (Test-Path -LiteralPath "work") {
            Remove-Item -LiteralPath "work" -Recurse -Force
        }
        Invoke-CheckedCommand -Executable $vlib -Arguments @("work")
        Invoke-CheckedCommand -Executable $vlog -Arguments @("-sv", "-f", "tb/filelist.f")
        $logName = "local_cdc_${axisHalfPeriod}ps.log"
        $temporaryLogs += $logName
        $testArguments = @{
            Top = "axis_preprocess_vector_cdc_tb"
            ExtraArguments = @("-gAXIS_HALF_PERIOD_PS=$axisHalfPeriod")
            PassMarker = "PASS: dual-clock AXI-Lite bridge matched 784 threshold outputs"
            LogName = $logName
        }
        Invoke-DirectedTest @testArguments
    }

    if (Test-Path -LiteralPath "work") {
        Remove-Item -LiteralPath "work" -Recurse -Force
    }
    Invoke-CheckedCommand -Executable $vlib -Arguments @("work")
    Invoke-CheckedCommand -Executable $vlog -Arguments @(
        "-sv",
        "-mfcu",
        "-L",
        "questa_uvm",
        "-f",
        "verif/uvm_axis/filelist.f"
    )

    Invoke-CheckedCommand -Executable $PythonExe -Arguments @("scripts/validate_vector_predictor.py")

    Write-Host "PASS: local directed RTL, three-ratio CDC/reset-abort stress, scalable sweep, UVM compile, and Python predictor checks completed."
}
finally {
    Pop-Location
    if (-not $KeepSimulatorOutputs) {
        foreach ($relativePath in @("work", "transcript", "vsim.wlf", "modelsim.ini") + $temporaryLogs) {
            $path = Join-Path $projectRoot $relativePath
            if (Test-Path -LiteralPath $path) {
                Remove-Item -LiteralPath $path -Recurse -Force
            }
        }
    }
}

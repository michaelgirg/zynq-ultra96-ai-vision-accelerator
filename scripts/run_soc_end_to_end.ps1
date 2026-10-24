[CmdletBinding()]
param(
    [string]$ToolchainBin = "",
    [string]$PythonExe = "python",
    [string]$CCompiler = "",
    [int[]]$AxisHalfPeriods = @(3333, 6500, 1850)
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$build = Join-Path $root "software/riscv/build/e2e"
$outputDir = Join-Path $root "generated/experiments/soc-e2e"
$library = "work_soc_e2e"
function Checked([string]$Exe, [string[]]$Arguments) {
    & $Exe @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Exe failed (exit $LASTEXITCODE)" }
}
Push-Location $root
try {
    $arguments = @("-ExecutionPolicy", "Bypass", "-File", "scripts/build_riscv_firmware.ps1",
        "-PythonExe", $PythonExe, "-BuildDir", $build, "-PollLimit", "1024")
    if ($ToolchainBin) { $arguments += @("-ToolchainBin", $ToolchainBin) }
    Checked "powershell" $arguments
    New-Item -ItemType Directory -Force $outputDir | Out-Null
    foreach ($period in $AxisHalfPeriods) {
        if ($period -le 0) { throw "Clock half-period must be positive" }
        # Fresh library per generic avoids old Starter incremental-vopt issues.
        $libraryPath = [IO.Path]::GetFullPath((Join-Path $root $library))
        if ($libraryPath -ne (Join-Path $root "work_soc_e2e")) { throw "Unsafe library path" }
        if (Test-Path -LiteralPath $libraryPath) { Remove-Item -LiteralPath $libraryPath -Recurse -Force }
        Checked "vlib" @($library)
        Checked "vlog" @("-work", $library, "-sv", "-f", "scripts/rtl_rv32_filelist.f",
            "+incdir+tb/riscv/integration/soc",
            "-f", "scripts/rtl_filelist.f", "rtl/riscv/soc/rv32_job_mailbox.sv",
            "tb/riscv/integration/soc/soc_sim_bus_pkg.sv",
            "tb/riscv/integration/soc/soc_dma_model.sv",
            "tb/riscv/integration/soc/rv32_soc_end_to_end_tb.sv")
        $captureDir = "generated/experiments/soc-e2e/${period}ps"
        New-Item -ItemType Directory -Force $captureDir | Out-Null
        $log = Join-Path $outputDir "soc_${period}ps.log"
        $result = & vsim -c "$library.rv32_soc_end_to_end_tb" "-gAXIS_HALF_PERIOD_PS=$period" `
            "+OUTPUT_DIR=$captureDir" `
            -l $log -do "onerror {quit -code 1}; onbreak {quit -code 1}; run -all; quit -f" 2>&1
        $exitCode = $LASTEXITCODE
        $result | ForEach-Object { Write-Host $_ }
        $text = $result -join "`n"
        if ($exitCode -ne 0 -or $text -match '\*\* (Error|Fatal):' -or
            $text -notmatch 'PASS: end-to-end SoC') { throw "SoC simulation failed; inspect $log" }
        $checkArgs = @("scripts/validate_soc_captures.py", "--capture-dir", $captureDir,
            "--report", "$captureDir/c_predictions.json")
        if ($CCompiler) { $checkArgs += @("--cc", $CCompiler) }
        Checked $PythonExe $checkArgs
    }
}
finally { Pop-Location }
Write-Host "PASS: firmware/portal/mailbox/CDC/DMA full-frame and recovery regression."

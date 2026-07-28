[CmdletBinding()]
param(
    [string]$ToolchainBin = "",
    [string]$PythonExe = "python"
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot

$buildArguments = @(
    "-ExecutionPolicy", "Bypass",
    "-File", (Join-Path $PSScriptRoot "build_riscv_firmware.ps1"),
    "-PythonExe", $PythonExe
)
if ($ToolchainBin) {
    $buildArguments += @("-ToolchainBin", $ToolchainBin)
}

& powershell @buildArguments
if ($LASTEXITCODE -ne 0) {
    throw "RV32 firmware build failed with exit code $LASTEXITCODE"
}

& powershell -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot "run_riscv_regression.ps1")
if ($LASTEXITCODE -ne 0) {
    throw "RV32 firmware regression failed with exit code $LASTEXITCODE"
}

Write-Host "PASS: GCC-built firmware and complete RV32IM regression passed."

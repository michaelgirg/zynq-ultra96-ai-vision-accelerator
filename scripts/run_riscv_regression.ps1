[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$simDir = Join-Path $repoRoot "sim\questa\riscv"
$vsim = Get-Command vsim -ErrorAction Stop

$runs = @(
    "run_unit.do",
    "run_pipeline_unit.do",
    "run_pipeline_core.do",
    "run_soc_unit.do"
)

Push-Location $simDir
try {
    foreach ($run in $runs) {
        Write-Host "Running RV32IM regression: $run"
        & $vsim.Source -c -do $run
        if ($LASTEXITCODE -ne 0) {
            throw "RV32IM regression failed in $run (exit $LASTEXITCODE)."
        }
    }
}
finally {
    Pop-Location
}

Write-Host "RV32IM baseline regression passed."

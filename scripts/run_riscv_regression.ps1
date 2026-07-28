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
        $output = & $vsim.Source -c -do $run 2>&1
        $exitCode = $LASTEXITCODE
        $output | ForEach-Object { Write-Host $_ }
        $transcript = $output -join "`n"
        if ($exitCode -ne 0 -or
            $transcript -match '(?m)^#?\s*\*\*\s+(Error|Fatal):' -or
            $transcript -match '(?m)\bFAIL:') {
            throw "RV32IM regression failed in $run (exit $exitCode)."
        }
    }
}
finally {
    Pop-Location
}

Write-Host "RV32IM baseline regression passed."

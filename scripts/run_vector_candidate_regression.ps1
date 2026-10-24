[CmdletBinding()]
param([string]$ModelDir = "generated/candidates/vector_conv4/classifier")

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$library = "work_vector_candidate"
$libraryPath = Join-Path $repoRoot $library
$vsim = (Get-Command vsim -ErrorAction Stop).Source
$vlib = (Get-Command vlib -ErrorAction Stop).Source
$vlog = (Get-Command vlog -ErrorAction Stop).Source
$modelPath = Join-Path $repoRoot $ModelDir
if (-not (Test-Path -LiteralPath (Join-Path $modelPath "vector_front_config.mem"))) {
    throw "Missing model configuration in $ModelDir; export the classifier first."
}

Push-Location $repoRoot
try {
    & $vlib $library
    if ($LASTEXITCODE -ne 0) { throw "Candidate simulation library creation failed" }
    & $vlog -work $library -sv -f tb/filelist.f
    if ($LASTEXITCODE -ne 0) { throw "Candidate RTL compilation failed" }
    foreach ($index in 0..7) {
        $sample = "sample_{0:D3}" -f $index
        $output = & $vsim -c "$library.axis_preprocess_vector_axi_lite_tb" +MODE=3 `
            "+VECTOR_CONFIG_MEM=$ModelDir/vector_front_config.mem" `
            "+INPUT_MEM=generated/test_vectors/${sample}_input.mem" `
            "+EXPECTED_MEM=$ModelDir/${sample}.mem" -do "run -all; quit -f" 2>&1
        $exitCode = $LASTEXITCODE
        $transcript = $output -join "`n"
        if ($exitCode -ne 0 -or $transcript -match '\*\* (Error|Fatal):' -or
            $transcript -notmatch 'PASS: AXI4-Stream selectable top mode 3 matched 2 frames x 784 pixels') {
            $output | ForEach-Object { Write-Host $_ }
            throw "Candidate RTL check failed for $sample"
        }
        Write-Host "PASS: candidate $sample matched 2 x 784 packed RTL outputs"
    }
}
finally {
    Pop-Location
    $resolved = [System.IO.Path]::GetFullPath($libraryPath)
    if ($resolved -eq (Join-Path $repoRoot "work_vector_candidate") -and (Test-Path -LiteralPath $resolved)) {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
Write-Host "PASS: candidate RTL matched 12,544 packed outputs using runtime-programmed coefficients."

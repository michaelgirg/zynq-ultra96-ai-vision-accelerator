[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$VitisPath,
    [Parameter(Mandatory=$true)][string]$ToolchainBin,
    [string]$Xsa,
    [string]$Workspace
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if (-not $Xsa) { $Xsa = Join-Path $root 'vivado/ultra96_v2_rv32_ai_vision_soc.xsa' }
if (-not $Workspace) { $Workspace = Join-Path $root 'vitis/vision_standalone' }
if (-not (Test-Path -LiteralPath $VitisPath)) { throw 'Vitis launcher missing' }
if (-not (Test-Path -LiteralPath $Xsa)) { throw 'XSA missing; complete Vivado implementation first' }
$previous = $env:VISION_VITIS_BUILD
$runId = [Guid]::NewGuid().ToString()
New-Item -ItemType Directory -Force -Path $Workspace | Out-Null
Push-Location $Workspace
try {
    $env:VISION_VITIS_BUILD = @{
        workspace = [IO.Path]::GetFullPath($Workspace)
        xsa = (Resolve-Path -LiteralPath $Xsa).Path
        toolchain_bin = (Resolve-Path -LiteralPath $ToolchainBin).Path
        run_id = $runId
    } | ConvertTo-Json -Compress
    & $VitisPath -s (Join-Path $PSScriptRoot 'build_vitis_application.py')
    if ($LASTEXITCODE -ne 0) { throw 'Vitis platform/application build failed' }
    # Some Vitis launchers return zero even when the Python script raises.
    $receipt = Join-Path $Workspace 'vision_build_evidence.json'
    if (-not (Test-Path -LiteralPath $receipt)) { throw 'No successful linked-build receipt was produced' }
    if ((Get-Content -LiteralPath $receipt -Raw | ConvertFrom-Json).run_id -ne $runId) {
        throw 'Vitis did not produce a successful receipt for this invocation'
    }
}
finally { $env:VISION_VITIS_BUILD = $previous; Pop-Location }

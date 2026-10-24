[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$VitisRoot,
    [Parameter(Mandatory=$true)][string]$ToolchainBin,
    [string]$ModelDir = "generated/candidates/vector_conv4/classifier"
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$bspRoot = Join-Path $VitisRoot "data/embeddedsw/lib/bsp"
$standalone = Get-ChildItem -LiteralPath $bspRoot -Directory |
    Where-Object { $_.Name -match '^standalone_v\d+_\d+$' } |
    Sort-Object Name -Descending | Select-Object -First 1
if (-not $standalone) { throw "No installed standalone BSP headers found" }
$gcc = Join-Path $ToolchainBin "aarch64-none-elf-gcc.exe"
if (-not (Test-Path -LiteralPath $gcc)) { throw "Missing AArch64 compiler" }
$build = Join-Path $root "software/riscv/build/a53-application"
New-Item -ItemType Directory -Force $build | Out-Null
$includes = @(
    (Join-Path $root "software/ultra96"),
    (Join-Path $root "software/riscv/include"),
    (Join-Path $root "software/riscv/build"),
    (Join-Path $root $ModelDir),
    (Join-Path $root "generated/test_vectors"),
    (Join-Path $root "tb/software/vitis_compile_contract"),
    (Join-Path $standalone.FullName "src/common"),
    (Join-Path $standalone.FullName "src/arm/ARMv8/64bit"),
    (Join-Path $standalone.FullName "src/arm/ARMv8"),
    (Join-Path $standalone.FullName "src/arm/common")
    (Join-Path $standalone.FullName "src/arm/common/gcc")
)
$flags = @("-std=c99", "-O2", "-Wall", "-Wextra", "-Werror", "-ffp-contract=off")
$manifest = Get-Content -LiteralPath (Join-Path $root "$ModelDir/manifest.json") -Raw | ConvertFrom-Json
$flags += "-DVISION_MODEL_SHA256=$($manifest.checkpoint_sha256)"
foreach ($path in $includes) { $flags += @("-I", $path) }
foreach ($name in @("vision_runtime", "vision_benchmark", "vector_front_reference",
        "vector_classifier", "vision_platform_vitis", "vision_demo_vitis")) {
    & $gcc @flags -c (Join-Path $root "software/ultra96/$name.c") -o (Join-Path $build "$name.o")
    if ($LASTEXITCODE -ne 0) { throw "AArch64 compilation failed: $name" }
}
Write-Host "PASS: six AArch64 application objects compiled against installed $($standalone.Name) headers."
Write-Host "Compile-only xparameters/bspconfig fixtures used; not a generated BSP, linked ELF or board run."

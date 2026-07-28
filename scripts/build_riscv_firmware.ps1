[CmdletBinding()]
param(
    [string]$ToolchainBin = "",
    [string]$PythonExe = "python",
    [string]$BuildDir = ""
)

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$softwareRoot = Join-Path $repoRoot "software\riscv"
if (-not $BuildDir) {
    $BuildDir = Join-Path $softwareRoot "build"
}
$BuildDir = [System.IO.Path]::GetFullPath($BuildDir)
New-Item -ItemType Directory -Force -Path $BuildDir | Out-Null

function Resolve-CrossTool {
    param([string]$Name)

    $executable = "riscv64-unknown-elf-$Name.exe"
    if ($ToolchainBin) {
        $candidate = Join-Path $ToolchainBin $executable
        if (-not (Test-Path -LiteralPath $candidate)) {
            throw "Missing RISC-V tool: $candidate"
        }
        return (Resolve-Path -LiteralPath $candidate).Path
    }

    $command = Get-Command $executable -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "Cannot find $executable; pass -ToolchainBin with the Vitis RISC-V bin directory."
    }
    return $command.Source
}

function Invoke-Checked {
    param(
        [string]$Executable,
        [string[]]$Arguments,
        [string]$Description
    )

    & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$Description failed with exit code $LASTEXITCODE"
    }
}

$gcc = Resolve-CrossTool "gcc"
$objcopy = Resolve-CrossTool "objcopy"
$objdump = Resolve-CrossTool "objdump"
$readelf = Resolve-CrossTool "readelf"
$size = Resolve-CrossTool "size"

$startupObject = Join-Path $BuildDir "startup.o"
$mainObject = Join-Path $BuildDir "main.o"
$elf = Join-Path $BuildDir "controller.elf"
$map = Join-Path $BuildDir "controller.map"
$imemBin = Join-Path $BuildDir "controller_imem.bin"
$dmemBin = Join-Path $BuildDir "controller_dmem.bin"
$imemMem = Join-Path $BuildDir "controller_imem.mem"
$dmemMem = Join-Path $BuildDir "controller_dmem.mem"
$disassembly = Join-Path $BuildDir "controller.dis"

$cflags = @(
    "-march=rv32im", "-mabi=ilp32", "-mcmodel=medany", "-O2", "-g",
    "-ffreestanding", "-fno-builtin", "-fno-common", "-Wall", "-Wextra",
    "-Werror", "-ffunction-sections", "-fdata-sections",
    "-I$(Join-Path $softwareRoot 'include')"
)

Invoke-Checked $gcc ($cflags + @(
    "-c", (Join-Path $softwareRoot "startup.S"), "-o", $startupObject
)) "startup compilation"
Invoke-Checked $gcc ($cflags + @(
    "-c", (Join-Path $softwareRoot "src\main.c"), "-o", $mainObject
)) "controller compilation"
Invoke-Checked $gcc ($cflags + @(
    "-nostdlib", "-nostartfiles", "-Wl,--build-id=none", "-Wl,--gc-sections",
    "-Wl,-Map,$map", "-T", (Join-Path $softwareRoot "linker.ld"),
    $startupObject, $mainObject, "-o", $elf
)) "firmware link"

$elfHeader = (& $readelf -h $elf 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0) {
    throw "ELF-header inspection failed with exit code $LASTEXITCODE"
}
if ($elfHeader -notmatch "Entry point address:\s+0x0(?:\s|$)") {
    throw "Firmware entry point is not reset vector 0x00000000"
}

$sectionHeaders = (& $objdump -h $elf 2>&1) -join "`n"
if ($LASTEXITCODE -ne 0) {
    throw "ELF-section inspection failed with exit code $LASTEXITCODE"
}
if ($sectionHeaders -notmatch "(?m)^\s*\d+\s+\.text\s+\S+\s+00000000\s") {
    throw "Firmware .text section is not linked at reset vector 0x00000000"
}

Invoke-Checked $objcopy @("-O", "binary", "--only-section=.text", $elf, $imemBin) "IMEM extraction"
Invoke-Checked $objcopy @("-O", "binary", "--only-section=.data", $elf, $dmemBin) "DMEM extraction"
Invoke-Checked $PythonExe @(
    (Join-Path $repoRoot "scripts\bin_to_riscv_mem.py"), $imemBin, $imemMem
) "IMEM packing"
Invoke-Checked $PythonExe @(
    (Join-Path $repoRoot "scripts\bin_to_riscv_mem.py"),
    "--offset-bytes", "0x8000", $dmemBin, $dmemMem
) "DMEM packing"

$disassemblyText = & $objdump -d -S $elf 2>&1
if ($LASTEXITCODE -ne 0) {
    throw "Disassembly generation failed with exit code $LASTEXITCODE"
}
$disassemblyText | Set-Content -LiteralPath $disassembly -Encoding ascii

Invoke-Checked $size @("-A", $elf) "firmware size report"
Write-Host "PASS: RV32 firmware built with entry point and .text at 0x00000000."
Write-Host "IMEM image: $imemMem"
Write-Host "DMEM image: $dmemMem"

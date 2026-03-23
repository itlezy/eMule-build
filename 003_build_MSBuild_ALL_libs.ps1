#Requires -Version 5.1
<#
.SYNOPSIS
  Build all eMule dependency libraries in parallel.

.PARAMETER Config
  Release (default) or Debug.

.EXAMPLE
  .\003_build_MSBuild_ALL_libs.ps1
  .\003_build_MSBuild_ALL_libs.ps1 -Config Debug
#>
param(
    [ValidateSet('Release', 'Debug')]
    [string]$Config = 'Release'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root   = $PSScriptRoot
$logDir = Join-Path $root "logs"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }

# --- Locate MSBuild via vswhere ---
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path $vswhere)) { throw "vswhere.exe not found — Visual Studio 2022 required." }
$msbuild = & $vswhere -latest -requires Microsoft.Component.MSBuild `
                      -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
if (-not $msbuild -or -not (Test-Path $msbuild)) { throw "MSBuild.exe not found via vswhere." }
Write-Host "MSBuild: $msbuild" -ForegroundColor DarkGray

# --- MSBuild job definitions ---
$msbuildDefs = @(
    @{ Name = 'cryptopp';     Proj = 'eMule-cryptopp\cryptlib.vcxproj' }
    @{ Name = 'id3lib';       Proj = 'eMule-id3lib\libprj\id3lib.vcxproj' }
    @{ Name = 'miniupnp';     Proj = 'eMule-miniupnp\miniupnpc\msvc\miniupnpc.vcxproj' }
    @{ Name = 'ResizableLib'; Proj = 'eMule-ResizableLib\ResizableLib\ResizableLib.vcxproj' }
    @{ Name = 'mbedtls';      Proj = 'eMule-mbedtls\visualc\VS2017\mbedTLS.vcxproj' }
)

Write-Host "`n=== Building all libs ($Config) ===" -ForegroundColor Cyan

# --- Start parallel MSBuild jobs ---
$jobEntries = [System.Collections.Generic.List[hashtable]]::new()
foreach ($def in $msbuildDefs) {
    $log  = Join-Path $logDir "$($def.Name)-$Config.log"
    $proj = Join-Path $root $def.Proj
    $job  = Start-Job -Name $def.Name -ScriptBlock {
        param($exe, $proj, $cfg, $log)
        & $exe $proj -target:Clean,Build "/property:Configuration=$cfg" /property:Platform=x64 `
               /nologo /verbosity:minimal *> $log
        $LASTEXITCODE
    } -ArgumentList $msbuild, $proj, $Config, $log
    Write-Host "  Started [$($def.Name)]"
    $jobEntries.Add(@{ Name = $def.Name; Job = $job; Log = $log })
}

# --- Start zlib job (cmake) ---
$zlibLog   = Join-Path $logDir "zlib-$Config.log"
$zlibBuild = Join-Path $root 'eMule-zlib\cmake-build'
$zlibJob   = Start-Job -Name 'zlib' -ScriptBlock {
    param($root, $zlibBuild, $cfg, $log)
    if (-not (Test-Path (Join-Path $zlibBuild 'CMakeCache.txt'))) {
        "cmake not configured — run setup.ps1 first" | Out-File $log
        return 1
    }
    cmake --build $zlibBuild --config $cfg --target zlibstatic *> $log
    if ($LASTEXITCODE -ne 0) { return $LASTEXITCODE }
    $libSrc = if ($cfg -eq 'Debug') { 'zsd.lib' } else { 'zs.lib' }
    $src    = Join-Path $zlibBuild "$cfg\$libSrc"
    $dest   = Join-Path $root "eMule-zlib\contrib\vstudio\vc\x64\$cfg"
    if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
    Copy-Item $src (Join-Path $dest 'zlib.lib') -Force
    return 0
} -ArgumentList $root, $zlibBuild, $Config, $zlibLog
Write-Host "  Started [zlib]"

# --- Wait and collect results ---
Write-Host "`n  Waiting for builds to complete ..."
$results = @{}

foreach ($entry in $jobEntries) {
    $exitCode          = Receive-Job -Job $entry.Job -Wait
    $results[$entry.Name] = ($exitCode -eq 0)
    Remove-Job -Job $entry.Job
}
$zlibExit       = Receive-Job -Job $zlibJob -Wait
$results['zlib'] = ($zlibExit -eq 0)
Remove-Job -Job $zlibJob

# --- Summary ---
Write-Host "`n=== Build Summary ($Config) ===" -ForegroundColor Cyan
$allOk = $true
foreach ($name in @('cryptopp', 'id3lib', 'miniupnp', 'ResizableLib', 'zlib', 'mbedtls')) {
    if ($results[$name]) {
        Write-Host "  [PASS] $name" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $name  — see logs\$name-$Config.log" -ForegroundColor Red
        $allOk = $false
    }
}

if (-not $allOk) {
    Write-Host "`nOne or more builds FAILED." -ForegroundColor Red
    exit 1
}
Write-Host "`nAll libraries built successfully." -ForegroundColor Green

#Requires -Version 5.1
<#
.SYNOPSIS
  One-time setup for eMule-build v0.72a workspace.
  Run after: git clone --recurse-submodules <this-repo>
             git checkout build-v0.72a

.DESCRIPTION
  1. Ensures submodules are at their pinned commits
  2. Applies patch files to each dep submodule
  3. Configures zlib cmake build

  VS 2022 (v143) + Windows SDK 10.0.26100.0 required.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$root = $PSScriptRoot

function Apply-Patch {
    param([string]$SubmoduleDir, [string]$PatchFile)
    $patchPath = Join-Path $root "patches\$PatchFile"
    if (-not (Test-Path $patchPath)) { throw "Patch not found: $patchPath" }
    Write-Host "  Applying $PatchFile ..."
    Push-Location (Join-Path $root $SubmoduleDir)
    try {
        git apply --3way $patchPath 2>&1 | ForEach-Object { "    $_" } | Write-Host
        if ($LASTEXITCODE -ne 0) { throw "git apply failed for $PatchFile" }
    } finally { Pop-Location }
}

Write-Host "`n=== Step 1: Submodule init ===" -ForegroundColor Cyan
git -C $root submodule update --init --recursive
if ($LASTEXITCODE -ne 0) { throw "git submodule update failed" }

Write-Host "`n=== Step 2: Apply dep patches ===" -ForegroundColor Cyan
Apply-Patch "eMule-cryptopp"     "cryptopp-CRYPTOPP_8_9_0.patch"
Apply-Patch "eMule-id3lib"       "id3lib-v3.9.1.patch"
Apply-Patch "eMule-miniupnp"     "miniupnpc-miniupnpc_2_3_3.patch"
Apply-Patch "eMule-ResizableLib" "resizablelib-master.patch"
Apply-Patch "eMule-zlib"         "zlib-v1.3.2.patch"
Apply-Patch "eMule-mbedtls"      "mbedtls-mbedtls-4.0.0.patch"

Write-Host "`n=== Step 3: Configure zlib cmake build ===" -ForegroundColor Cyan
$zlibBuild = Join-Path $root "eMule-zlib\cmake-build"
if (-not (Test-Path (Join-Path $zlibBuild "CMakeCache.txt"))) {
    Write-Host "  Running cmake configure for zlib ..."
    cmake -S (Join-Path $root "eMule-zlib") `
          -B $zlibBuild `
          -G "Visual Studio 17 2022" -A x64 `
          -DZLIB_BUILD_SHARED=OFF `
          -DZLIB_BUILD_TESTING=OFF `
          "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded`$<`$<CONFIG:Debug>:Debug>"
    if ($LASTEXITCODE -ne 0) { throw "cmake configure failed" }
} else {
    Write-Host "  cmake already configured (cmake-build\CMakeCache.txt exists)"
}

Write-Host "`n=== Setup complete ===" -ForegroundColor Green
Write-Host "Next: run 003_build_MSBuild_ALL_libs.cmd, then 004_build_MSBuild_eMule.cmd"

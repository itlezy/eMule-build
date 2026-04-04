#Requires -Version 7.2
[CmdletBinding()]
param(
    [string]$SourceRepo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
    [string]$Branch = 'v0.72a',
    [string]$WorkRoot = (Join-Path ([IO.Path]::GetTempPath()) 'eMule-build-smoke'),
    [switch]$KeepWorkspace
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Resolve-Tool([string[]]$Names) {
    foreach ($name in $Names) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    $null
}

function Invoke-Step([string]$Workspace, [string[]]$Arguments) {
    $pwsh = Resolve-Tool @('pwsh.exe', 'pwsh')
    if (-not $pwsh) {
        throw 'pwsh not found on PATH.'
    }
    Write-Host ("> {0}" -f ($Arguments -join ' ')) -ForegroundColor Cyan
    & $pwsh -NoLogo -NoProfile -File (Join-Path $Workspace 'workspace.ps1') @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "workspace.ps1 $($Arguments -join ' ') failed with exit code $LASTEXITCODE."
    }
}

$git = Resolve-Tool @('git.exe', 'git')
if (-not $git) {
    throw 'git not found on PATH.'
}

$sourceRepoPath = (Resolve-Path $SourceRepo).Path
$workspaceName = 'bbclean-smoke-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmss')
$null = New-Item -ItemType Directory -Path $WorkRoot -Force
$workspace = Join-Path $WorkRoot $workspaceName

try {
    Write-Host "Cloning $sourceRepoPath -> $workspace" -ForegroundColor Cyan
    & $git clone --branch $Branch $sourceRepoPath $workspace
    if ($LASTEXITCODE -ne 0) {
        throw "git clone failed with exit code $LASTEXITCODE."
    }

    & $git -C $workspace submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) {
        throw "git submodule update failed with exit code $LASTEXITCODE."
    }

    Invoke-Step $workspace @('clean-generated')
    Invoke-Step $workspace @('repair')
    Invoke-Step $workspace @('validate')
    Invoke-Step $workspace @('package')
    Invoke-Step $workspace @('validate')

    Write-Host "Smoke test passed: $workspace" -ForegroundColor Green
} finally {
    if (-not $KeepWorkspace -and (Test-Path -LiteralPath $workspace)) {
        Remove-Item -LiteralPath $workspace -Recurse -Force
    }
}

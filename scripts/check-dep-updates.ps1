#Requires -Version 7.2
<#
.SYNOPSIS
    Checks upstream repositories for newer releases relative to the currently tracked dependency versions.
.DESCRIPTION
    Queries each dependency's upstream remote for new tags or commits without modifying
    local repositories. For tagged deps, compares semver; for master-tracked deps, compares
    the upstream HEAD SHA against the known base commit.
.EXAMPLE
    pwsh -File scripts\check-dep-updates.ps1
#>

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

# ── git helpers ────────────────────────────────────────────────────────────────

function Get-GitExe {
    $cmd = Get-Command git -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { throw 'git not found on PATH.' }
    $cmd.Source
}

function Get-RemoteTags([string]$Remote) {
    $git = Get-GitExe
    $lines = & $git ls-remote --tags --refs $Remote 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git ls-remote --tags failed: $($lines -join ' ')" }
    $lines | ForEach-Object {
        if ($_ -match '^[0-9a-f]{40}\s+refs/tags/(.+)$') { $Matches[1] }
    }
}

function Get-RemoteHeadSha([string]$Remote) {
    $git = Get-GitExe
    $line = & $git ls-remote $Remote HEAD 2>&1 | Select-Object -First 1
    if ($LASTEXITCODE -ne 0) { throw "git ls-remote HEAD failed: $line" }
    if ($line -match '^([0-9a-f]{40})\s') { $Matches[1] } else { $null }
}

# ── version helpers ────────────────────────────────────────────────────────────

function ConvertTo-Version([string]$Tag, [string]$Pattern) {
    # Returns a [version] object if the tag matches the pattern with 3 capture groups (major, minor, patch)
    if ($Tag -match $Pattern) {
        try { [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])" } catch { $null }
    } else { $null }
}

function Find-NewerTags([string[]]$AllTags, [string]$Pattern, [version]$BaseVer) {
    $allVersioned = $AllTags | ForEach-Object {
        $v = ConvertTo-Version $_ $Pattern
        if ($v) { [pscustomobject]@{ Tag = $_; Version = $v } }
    }
    @($allVersioned | Where-Object { $_.Version -gt $BaseVer } | Sort-Object Version -Descending)
}

# ── dependency definitions ─────────────────────────────────────────────────────
#
#   Kind 'tagged'  — tracks a specific upstream release tag; checks for newer semver tags
#   Kind 'master'  — tracks upstream master; checks whether HEAD has moved from the base commit
#   Kind 'custom'  — internal/fork with no external upstream to compare against

$Deps = @(
    [pscustomobject]@{
        Name       = 'cryptopp'
        Kind       = 'tagged'
        Remote     = 'https://github.com/weidai11/cryptopp.git'
        BaseTag    = 'CRYPTOPP_8_9_0'
        Pattern    = '^CRYPTOPP_(\d+)_(\d+)_(\d+)$'
    }
    [pscustomobject]@{
        Name       = 'id3lib'
        Kind       = 'custom'
        BaseTag    = 'v3.9.1'
        Note       = 'Patch baked into itlezy/eMule-id3lib branch — no external upstream'
    }
    [pscustomobject]@{
        Name       = 'miniupnp'
        Kind       = 'tagged'
        Remote     = 'https://github.com/miniupnp/miniupnp.git'
        BaseTag    = 'miniupnpc_2_3_3'
        Pattern    = '^miniupnpc_(\d+)_(\d+)_(\d+)$'
    }
    [pscustomobject]@{
        Name       = 'ResizableLib'
        Kind       = 'master'
        Remote     = 'https://github.com/ppescher/resizablelib.git'
        BaseCommit = 'bebab50a5dbfbb0913b64d23b86d1c3110677c41'
    }
    [pscustomobject]@{
        Name       = 'zlib'
        Kind       = 'tagged'
        Remote     = 'https://github.com/madler/zlib.git'
        BaseTag    = 'v1.3.2'
        Pattern    = '^v(\d+)\.(\d+)\.(\d+)$'
    }
    [pscustomobject]@{
        Name       = 'mbedtls'
        Kind       = 'tagged'
        Remote     = 'https://github.com/Mbed-TLS/mbedtls.git'
        BaseTag    = 'mbedtls-4.0.0'
        Pattern    = '^mbedtls-(\d+)\.(\d+)\.(\d+)$'
    }
    [pscustomobject]@{
        Name       = 'tf-psa-crypto'
        Kind       = 'tagged'
        Remote     = 'https://github.com/Mbed-TLS/TF-PSA-Crypto.git'
        BaseTag    = 'v1.0.0'
        Pattern    = '^v(\d+)\.(\d+)\.(\d+)$'
    }
)

# ── check each dependency ──────────────────────────────────────────────────────

$W = @{ Name = 20; Current = 24; Latest = 24; Detail = 0 }

function Write-Header {
    $fmt  = "  {0,-$($W.Name)}  {1,-$($W.Current)}  {2,-$($W.Latest)}  {3}"
    $line = $fmt -f 'DEPENDENCY', 'CURRENT', 'LATEST', 'NOTES'
    Write-Host ''
    Write-Host $line -ForegroundColor DarkGray
    Write-Host ('  ' + ('─' * ($W.Name + $W.Current + $W.Latest + 12))) -ForegroundColor DarkGray
}

function Write-Row([string]$Name, [string]$Status, [string]$Current, [string]$Latest, [string]$Detail) {
    $fg = switch ($Status) {
        'up-to-date' { 'Green' }
        'update'     { 'Yellow' }
        'custom'     { 'DarkGray' }
        'error'      { 'Red' }
        default      { 'White' }
    }
    $icon = switch ($Status) {
        'up-to-date' { [char]0x2713 }  # ✓
        'update'     { [char]0x25B2 }  # ▲
        'custom'     { '-' }
        'error'      { [char]0x2717 }  # ✗
        default      { '?' }
    }
    $fmt  = "  {0} {1,-$($W.Name)}  {2,-$($W.Current)}  {3,-$($W.Latest)}  {4}"
    $line = $fmt -f $icon, $Name, $Current, $Latest, $Detail
    Write-Host $line -ForegroundColor $fg
}

Write-Host ''
Write-Host '  Dependency upstream check' -ForegroundColor Cyan

Write-Header

$results = [System.Collections.Generic.List[pscustomobject]]::new()

foreach ($dep in $Deps) {
    $r = [pscustomobject]@{
        Name    = $dep.Name
        Status  = 'unknown'
        Current = ''
        Latest  = ''
        Detail  = ''
    }

    try {
        switch ($dep.Kind) {

            'custom' {
                $r.Status  = 'custom'
                $r.Current = $dep.BaseTag
                $r.Latest  = 'N/A'
                $r.Detail  = $dep.Note
            }

            'tagged' {
                $baseVer = ConvertTo-Version $dep.BaseTag $dep.Pattern
                if (-not $baseVer) { throw "Cannot parse base tag '$($dep.BaseTag)' with pattern '$($dep.Pattern)'" }

                $allTags = @(Get-RemoteTags $dep.Remote)
                $newer   = @(Find-NewerTags $allTags $dep.Pattern $baseVer)

                $r.Current = $dep.BaseTag
                if ($newer.Count -gt 0) {
                    $r.Status  = 'update'
                    $r.Latest  = $newer[0].Tag
                    $r.Detail  = "$($newer.Count) newer release(s) available"
                } else {
                    $r.Status  = 'up-to-date'
                    $r.Latest  = $dep.BaseTag
                    $r.Detail  = 'on latest matching release'
                }
            }

            'master' {
                $remoteHead = Get-RemoteHeadSha $dep.Remote
                $r.Current  = $dep.BaseCommit.Substring(0, 8)
                $r.Latest   = $remoteHead ? $remoteHead.Substring(0, 8) : '?'

                if ($remoteHead -and $remoteHead -ne $dep.BaseCommit) {
                    $r.Status  = 'update'
                    $r.Detail  = 'upstream master has moved since base commit'
                } else {
                    $r.Status  = 'up-to-date'
                    $r.Detail  = 'base commit matches upstream HEAD'
                }
            }
        }
    } catch {
        $r.Status  = 'error'
        $r.Current = $dep.BaseTag ?? $dep.BaseCommit ?? ''
        $r.Latest  = '?'
        $r.Detail  = $_.Exception.Message
    }

    $results.Add($r)
    Write-Row $r.Name $r.Status $r.Current $r.Latest $r.Detail
}

# ── summary ────────────────────────────────────────────────────────────────────

Write-Host ('  ' + ('─' * ($W.Name + $W.Current + $W.Latest + 12))) -ForegroundColor DarkGray
Write-Host ''

$upToDate = @($results | Where-Object Status -eq 'up-to-date')
$updates  = @($results | Where-Object Status -eq 'update')
$customs  = @($results | Where-Object Status -eq 'custom')
$errors   = @($results | Where-Object Status -eq 'error')

Write-Host '  Summary' -ForegroundColor Cyan
Write-Host "    Up-to-date : $($upToDate.Count)" -ForegroundColor $(if ($upToDate.Count) { 'Green' } else { 'DarkGray' })

if ($updates.Count -gt 0) {
    Write-Host "    Updates    : $($updates.Count)  [$( ($updates | ForEach-Object { "$($_.Name) → $($_.Latest)" }) -join ', ')]" -ForegroundColor Yellow
} else {
    Write-Host "    Updates    : 0" -ForegroundColor Green
}

if ($customs.Count -gt 0) {
    Write-Host "    Custom     : $($customs.Count)  [$($customs.Name -join ', ')]" -ForegroundColor DarkGray
}

if ($errors.Count -gt 0) {
    Write-Host "    Errors     : $($errors.Count)  [$($errors.Name -join ', ')]" -ForegroundColor Red
}

Write-Host ''

# Exit 1 if any updates are available (useful for CI)
exit ($updates.Count -gt 0 ? 1 : 0)

#Requires -Version 7.6
<#
.SYNOPSIS
Canonical build, validation, test, live-test, and release-package entrypoint for
an already materialized eMule BB workspace.

.DESCRIPTION
This script owns operational build/test orchestration for the canonical
workspace. It assumes eMulebb-setup has already materialized the repo pool,
managed app worktrees, generated workspace manifest, and dependency layout.
Run `pwsh -File .\workspace.ps1 help` for supported commands and common
options.
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('help','env-check','dep-status','validate','build-libs','build-app','build-tests','python-tests','test','live-diff','live-e2e','amutorrent-session','community-core-coverage','package-release','build-all','full')]
    [string]$Command = 'help',

    [string]$EmuleWorkspaceRoot,

    [ValidateSet('Release', 'Debug')]
    [string]$Config = 'Release',

    [ValidateSet('x64', 'ARM64')]
    [string]$Platform = 'x64',

    [ValidateSet('Full', 'Warnings', 'ErrorsOnly')]
    [string]$BuildOutputMode = 'ErrorsOnly',

    [switch]$Clean,

    [string]$WorkspaceName,

    [string]$TestRunVariant,

    [string]$BaselineVariant,

    [string[]]$AppVariant,

    [string[]]$LiveSuite,

    [string[]]$PythonTestPath,

    [string]$PythonTestExpression,

    [switch]$PythonTestQuiet,

    [string[]]$PythonTestArgs,

    [switch]$LiveFailFast,

    [switch]$SkipLiveSeedRefresh,

    [switch]$LiveNetwork,

    [int]$RestServerSearchCount = 6,

    [int]$RestKadSearchCount = 6,

    [int]$RestDownloadTriggerCount = 1,

    [ValidateSet('', 'automatic', 'server', 'global', 'kad')]
    [string]$RestSearchMethodOverride = '',

    [ValidateSet('http', 'https')]
    [string]$RestWebServerScheme = 'http',

    [ValidateSet('smoke', 'contract', 'contract-stress')]
    [string]$RestCoverageBudget = 'contract',

    [ValidateSet('off', 'smoke', 'soak')]
    [string]$RestStressBudget = 'smoke',

    [double]$RestStressDurationSeconds = 30.0,

    [int]$RestStressConcurrency = 4,

    [int]$RestStressMaxFailures = 1,

    [double]$RestStressRequestTimeoutSeconds = 5.0,

    [ValidateSet('off', 'smoke')]
    [string]$RestSocketAdversityBudget = 'off',

    [ValidateSet('off', 'smoke')]
    [string]$RestTlsHandshakeAdversityBudget = 'off',

    [ValidateSet('off', 'smoke', 'soak')]
    [string]$RestLeakChurnBudget = 'off',

    [int]$RestLeakChurnCycles = -1,

    [switch]$RestStopStartAfterChurn,

    [int]$RestColdStartDumpStressWaves = 4,

    [int]$RestColdStartDumpStressSearchesPerWave = 12,

    [int]$RestColdStartDumpStressMaxConcurrentSearches = 8,

    [int]$RestColdStartDumpStressDownloadsPerWave = 12,

    [double]$RestColdStartDumpStressPostDrainSeconds = 30.0,

    [double]$RestColdStartDumpStressToolTimeoutSeconds = 600.0,

    [switch]$RestColdStartDumpStressEnableUmdh,

    [switch]$RestColdStartDumpStressSkipDumps,

    [ValidateSet('required', 'optional')]
    [string]$StartupTraceMode = 'required',

    [string]$SharedRoot,

    [int]$SharedFilesTreeStressChurnCycles = -1,

    [string]$ReleaseVersion = '1.1.1',

    [string]$P2PBindInterfaceName = 'hide.me',

    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Write-WorkspaceHelp {
    @'
eMule-build workspace orchestration

Purpose:
  Build, validate, test, live-test, and package an already materialized
  canonical eMule BB workspace.

Usage:
  pwsh -File .\workspace.ps1 help
  pwsh -File .\workspace.ps1 <command> -EmuleWorkspaceRoot <workspace-root> [options]

Commands:
  help                     Show this help.
  env-check                Verify Git, Visual Studio, and MSBuild discovery.
  dep-status               Report dependency and app worktree status.
  validate                 Run workspace validation and shared policy audits.
  build-libs               Build shared dependencies.
  build-app                Build canonical app variants.
  build-tests              Build the shared test harness.
  python-tests             Run pytest-based harness checks.
  test                     Run parity, coverage, and live-diff checks.
  live-diff                Compare two configured app variants.
  live-e2e                 Run aggregate live E2E suites.
  amutorrent-session       Start an interactive aMuTorrent test session.
  community-core-coverage  Run community-core coverage checks.
  package-release          Build the main app and create release package artifacts.
  build-all                Run build-libs, build-app, and build-tests.
  full                     Run build-all, test, and a workspace summary.

Common options:
  -EmuleWorkspaceRoot <path>  Workspace root. Defaults to EMULE_WORKSPACE_ROOT.
  -WorkspaceName <name>       Workspace name. Defaults to deps.psd1.
  -Config Debug|Release       Build configuration. Default: Release.
  -Platform x64|ARM64         Build platform. Default: x64.
  -ReleaseVersion <version>   Package release version. Default: 1.1.1.
  -BuildOutputMode <mode>     Full, Warnings, or ErrorsOnly. Default: ErrorsOnly.
  -Clean                      Clean selected build outputs before building.
  -Help                       Show this help.
'@ | Write-Host
}

if ($Help -or $Command -eq 'help') {
    Write-WorkspaceHelp
    return
}

$ScriptRoot = Split-Path -Parent $PSCommandPath
$Manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $ScriptRoot 'deps.psd1')
$Workspace = $Manifest.Workspace
$WorkspaceName = if ([string]::IsNullOrWhiteSpace($WorkspaceName)) { $Workspace.Name } else { $WorkspaceName }
$EmuleWorkspaceRoot = if ([string]::IsNullOrWhiteSpace($EmuleWorkspaceRoot)) {
    if (-not [string]::IsNullOrWhiteSpace($env:EMULE_WORKSPACE_ROOT)) {
        $env:EMULE_WORKSPACE_ROOT
    } else {
        throw 'EMULE_WORKSPACE_ROOT or -EmuleWorkspaceRoot is required.'
    }
} else {
    $EmuleWorkspaceRoot
}
$EmuleWorkspaceRoot = [System.IO.Path]::GetFullPath($EmuleWorkspaceRoot)
$WorkspaceRootPath = [System.IO.Path]::GetFullPath((Join-Path $EmuleWorkspaceRoot ("workspaces\{0}" -f $WorkspaceName)))

$WorkspaceManifestPath = Join-Path $EmuleWorkspaceRoot ("workspaces\{0}\deps.psd1" -f $WorkspaceName)
if (-not (Test-Path -LiteralPath $WorkspaceManifestPath -PathType Leaf)) {
    throw "Workspace manifest is missing: $WorkspaceManifestPath. Run eMulebb-setup init/materialize/sync for this workspace."
}

$WorkspaceManifest = Import-PowerShellDataFile -LiteralPath $WorkspaceManifestPath
$WorkspaceTopology = if ($WorkspaceManifest.ContainsKey('Workspace')) { $WorkspaceManifest.Workspace } else { $null }
if ($null -eq $WorkspaceTopology) {
    throw "Workspace manifest '$WorkspaceManifestPath' does not define a Workspace block."
}

$convertWorkspaceRelativePathToRootRelative = {
    param([string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return $RelativePath
    }

    $absolutePath = [System.IO.Path]::GetFullPath((Join-Path $WorkspaceRootPath $RelativePath))
    [System.IO.Path]::GetRelativePath($EmuleWorkspaceRoot, $absolutePath)
}

if (-not ($WorkspaceTopology.ContainsKey('AppRepo') -and $WorkspaceTopology.AppRepo.ContainsKey('SeedRepo') -and $WorkspaceTopology.AppRepo.ContainsKey('Variants'))) {
    throw "Workspace manifest '$WorkspaceManifestPath' is missing AppRepo.SeedRepo or AppRepo.Variants."
}

if (-not $WorkspaceTopology.ContainsKey('Repos')) {
    throw "Workspace manifest '$WorkspaceManifestPath' is missing Repos."
}

$Workspace.AppRepo.SeedRepo = @{} + $WorkspaceTopology.AppRepo.SeedRepo
if ($Workspace.AppRepo.SeedRepo.ContainsKey('Path')) {
    $Workspace.AppRepo.SeedRepo.Path = & $convertWorkspaceRelativePathToRootRelative $Workspace.AppRepo.SeedRepo.Path
}

$normalizedVariants = [System.Collections.Generic.List[hashtable]]::new()
foreach ($variant in @($WorkspaceTopology.AppRepo.Variants)) {
    $normalizedVariant = @{} + $variant
    if ($normalizedVariant.ContainsKey('Path')) {
        $normalizedVariant.Path = & $convertWorkspaceRelativePathToRootRelative $normalizedVariant.Path
    }
    $normalizedVariants.Add($normalizedVariant) | Out-Null
}
$Workspace.AppRepo.Variants = @($normalizedVariants)

if (-not $Workspace.ContainsKey('Repos') -or $null -eq $Workspace.Repos) {
    $Workspace.Repos = @{}
}

foreach ($repoKey in $WorkspaceTopology.Repos.Keys) {
    $Workspace.Repos[$repoKey] = & $convertWorkspaceRelativePathToRootRelative $WorkspaceTopology.Repos[$repoKey]
}

$Dependencies = @($Workspace.Dependencies)
$AppRepo = $Workspace.AppRepo
$TestTargets = $AppRepo.TestTargets
$ToolsetOverrideVariable = $Workspace.Toolchain.ToolsetOverrideVariable

function Resolve-WorkspacePath([string]$RelativePath) {
    [System.IO.Path]::GetFullPath((Join-Path $EmuleWorkspaceRoot $RelativePath))
}

function Ensure-Directory([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) {
        $null = New-Item -ItemType Directory -Path $Path -Force
    }
}

function Get-WorkspaceRoot {
    Resolve-WorkspacePath ("workspaces\{0}" -f $WorkspaceName)
}

function Get-WorkspaceStateRoot {
    Resolve-WorkspacePath ("workspaces\{0}\state" -f $WorkspaceName)
}

function Convert-ToFileToken([string]$Value) {
    $token = ($Value -replace '[\\/:*?"<>|\s]+', '-') -replace '[^A-Za-z0-9._-]+', '-'
    $token = $token.Trim('-')
    if ([string]::IsNullOrWhiteSpace($token)) {
        return 'build'
    }

    $token
}

function Get-BuildLogSessionStamp {
    if (-not (Get-Variable -Name BuildLogSessionStamp -Scope Script -ErrorAction SilentlyContinue)) {
        $script:BuildLogSessionStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    }

    $script:BuildLogSessionStamp
}

function Get-BuildLogDirectory {
    $buildLogsRoot = Join-Path (Get-WorkspaceStateRoot) 'build-logs'
    Ensure-Directory -Path $buildLogsRoot

    $sessionDirectory = Join-Path $buildLogsRoot (Get-BuildLogSessionStamp)
    Ensure-Directory -Path $sessionDirectory

    $sessionDirectory
}

function Get-BuildRecapSummaryPath {
    Join-Path (Get-BuildLogDirectory) 'summary.json'
}

function Get-WorkspaceCommandLockMetadataPath {
    Join-Path (Get-WorkspaceStateRoot) 'active-command-lock.json'
}

function Get-WorkspaceCommandLockName {
    $normalizedRoot = $EmuleWorkspaceRoot.TrimEnd('\').ToLowerInvariant()
    $hashBytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($normalizedRoot))
    $hash = [System.Convert]::ToHexString($hashBytes)
    "Global\eMuleBuild-$hash"
}

function Get-WorkspaceCommandLockMetadata {
    $metadataPath = Get-WorkspaceCommandLockMetadataPath
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        return $null
    }

    try {
        Get-Content -Raw -LiteralPath $metadataPath | ConvertFrom-Json -ErrorAction Stop
    } catch {
        $null
    }
}

function Set-WorkspaceCommandLockMetadata {
    Ensure-Directory -Path (Get-WorkspaceStateRoot)
    $metadata = [ordered]@{
        command = $Command
        pid = $PID
        machine_name = $env:COMPUTERNAME
        started_utc = (Get-Date).ToUniversalTime().ToString('o')
        workspace_root = $EmuleWorkspaceRoot
        workspace_name = $WorkspaceName
        config = $Config
        platform = $Platform
    }

    $metadata | ConvertTo-Json | Set-Content -LiteralPath (Get-WorkspaceCommandLockMetadataPath) -Encoding utf8
}

function Remove-WorkspaceCommandLockMetadata {
    $metadataPath = Get-WorkspaceCommandLockMetadataPath
    if (-not (Test-Path -LiteralPath $metadataPath -PathType Leaf)) {
        return
    }

    try {
        Remove-Item -LiteralPath $metadataPath -Force
    } catch {
    }
}

function Write-WorkspaceCommandLockConflict {
    $metadata = Get-WorkspaceCommandLockMetadata
    if ($metadata) {
        Write-Host ("Workspace busy: command '{0}' cannot start for {1}. This single-owner workspace lock is intentional. Active owner: '{2}' (PID {3} on {4}, started {5}). Wait for that command to finish and retry." -f $Command, $EmuleWorkspaceRoot, $metadata.command, $metadata.pid, $metadata.machine_name, $metadata.started_utc) -ForegroundColor Yellow
        return
    }

    Write-Host ("Workspace busy: command '{0}' cannot start for {1} because another eMule-build command intentionally holds the single-owner workspace lock. Wait briefly and retry." -f $Command, $EmuleWorkspaceRoot) -ForegroundColor Yellow
}

function Acquire-WorkspaceCommandLock {
    $script:WorkspaceCommandMutex = [System.Threading.Mutex]::new($false, (Get-WorkspaceCommandLockName))
    $acquired = $false
    try {
        try {
            $acquired = $script:WorkspaceCommandMutex.WaitOne(0)
        } catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
        }

        if (-not $acquired) {
            Write-WorkspaceCommandLockConflict
            $script:WorkspaceCommandMutex.Dispose()
            $script:WorkspaceCommandMutex = $null
            return $false
        }

        Set-WorkspaceCommandLockMetadata
        $script:WorkspaceCommandLockAcquired = $true
        return $true
    } catch {
        if ($acquired) {
            try {
                $script:WorkspaceCommandMutex.ReleaseMutex()
            } catch {
            }
        }
        if ($script:WorkspaceCommandMutex) {
            $script:WorkspaceCommandMutex.Dispose()
            $script:WorkspaceCommandMutex = $null
        }
        throw
    }
}

function Release-WorkspaceCommandLock {
    if (-not (Get-Variable -Name WorkspaceCommandLockAcquired -Scope Script -ErrorAction SilentlyContinue)) {
        return
    }

    if ($script:WorkspaceCommandLockAcquired -and $script:WorkspaceCommandMutex) {
        Remove-WorkspaceCommandLockMetadata
        try {
            $script:WorkspaceCommandMutex.ReleaseMutex()
        } catch {
        }
        $script:WorkspaceCommandMutex.Dispose()
    }

    $script:WorkspaceCommandMutex = $null
    $script:WorkspaceCommandLockAcquired = $false
}

function Reset-BuildExecutionState {
    $script:BuildStepResults = [System.Collections.Generic.List[object]]::new()
    $script:BuildCommandStartedAt = Get-Date
    $null = Get-BuildLogDirectory
}

function Get-WarningCountFromLog([string]$LogPath) {
    if ([string]::IsNullOrWhiteSpace($LogPath) -or -not (Test-Path -LiteralPath $LogPath -PathType Leaf)) {
        return 0
    }

    $warningPattern = '(?i)\bwarning\b'
    $summaryPattern = '(?i)^\s*\d+\s+warning\(s\)\s*$'
    @(Get-Content -LiteralPath $LogPath | Where-Object {
        $_ -match $warningPattern -and $_ -notmatch $summaryPattern
    }).Count
}

function Format-Duration([double]$TotalSeconds) {
    if ($TotalSeconds -lt 10) {
        return ('{0:N1}s' -f $TotalSeconds)
    }

    ('{0:N0}s' -f [Math]::Round($TotalSeconds))
}

function Add-BuildStepResult(
    [string]$StepName,
    [bool]$Succeeded,
    [string]$LogPath,
    [string]$BinaryLogPath,
    [double]$DurationSeconds,
    [int]$WarningCount
) {
    if (-not (Get-Variable -Name BuildStepResults -Scope Script -ErrorAction SilentlyContinue)) {
        $script:BuildStepResults = [System.Collections.Generic.List[object]]::new()
    }

    $script:BuildStepResults.Add([pscustomobject]@{
        Name = $StepName
        Succeeded = $Succeeded
        LogPath = $LogPath
        BinaryLogPath = $BinaryLogPath
        DurationSeconds = $DurationSeconds
        WarningCount = $WarningCount
    }) | Out-Null
}

function Write-BuildStepSummary(
    [string]$StepName,
    [bool]$Succeeded,
    [string]$LogPath,
    [double]$DurationSeconds
) {
    $durationText = Format-Duration $DurationSeconds
    if ($Succeeded) {
        if ($BuildOutputMode -eq 'Full') {
            return
        }

        Write-Host ("OK   {0} ({1})" -f $StepName, $durationText) -ForegroundColor Green
        return
    }

    $line = "FAIL {0} ({1})" -f $StepName, $durationText
    if (-not [string]::IsNullOrWhiteSpace($LogPath)) {
        $line += " -> $LogPath"
    }
    Write-Host $line -ForegroundColor Red
}

function Write-BuildCommandRecap([string]$CommandName) {
    if (-not (Get-Variable -Name BuildStepResults -Scope Script -ErrorAction SilentlyContinue)) {
        return
    }

    $steps = @($script:BuildStepResults)
    if ($steps.Count -eq 0) {
        return
    }

    $failedCount = @($steps | Where-Object { -not $_.Succeeded }).Count
    $totalDurationSeconds = (($steps | Measure-Object -Property DurationSeconds -Sum).Sum)
    $totalWarningCount = (($steps | Measure-Object -Property WarningCount -Sum).Sum)
    $summary = [ordered]@{
        command = $CommandName
        workspace_root = $EmuleWorkspaceRoot
        workspace_name = $WorkspaceName
        config = $Config
        platform = $Platform
        clean = [bool]$Clean
        build_output_mode = $BuildOutputMode
        started_utc = $script:BuildCommandStartedAt.ToUniversalTime().ToString('o')
        completed_utc = (Get-Date).ToUniversalTime().ToString('o')
        total_duration_seconds = [Math]::Round($totalDurationSeconds, 3)
        total_warning_count = $totalWarningCount
        log_directory = Get-BuildLogDirectory
        failed_steps = $failedCount
        step_count = $steps.Count
        steps = @($steps | ForEach-Object {
            [ordered]@{
                name = $_.Name
                succeeded = $_.Succeeded
                duration_seconds = [Math]::Round($_.DurationSeconds, 3)
                warning_count = $_.WarningCount
                log_path = $_.LogPath
                binary_log_path = $_.BinaryLogPath
            }
        })
    }

    $summary | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Get-BuildRecapSummaryPath) -Encoding utf8

    Write-Host ''
    Write-Host ("Build recap: {0}" -f $CommandName) -ForegroundColor Green
    foreach ($step in $steps) {
        $status = if ($step.Succeeded) { 'OK  ' } else { 'FAIL' }
        Write-Host ("{0} {1} ({2}, {3} warnings)" -f $status, $step.Name, (Format-Duration $step.DurationSeconds), $step.WarningCount)
    }
    Write-Host ("Steps: {0}" -f $steps.Count)
    Write-Host ("Failures: {0}" -f $failedCount)
    Write-Host ("Warnings: {0}" -f $totalWarningCount)
    Write-Host ("Duration: {0}" -f (Format-Duration $totalDurationSeconds))
    Write-Host ("Logs: {0}" -f (Get-BuildLogDirectory)) -ForegroundColor DarkGray
    Write-Host ("Summary: {0}" -f (Get-BuildRecapSummaryPath)) -ForegroundColor DarkGray
}

function Resolve-Tool([string[]]$Names) {
    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            return $command.Source
        }
    }
    $null
}

function Get-PythonInvocation {
    $python = Resolve-Tool @('python.exe', 'python')
    if ($python) {
        return @{
            FilePath = $python
            Prefix = @()
        }
    }

    $py = Resolve-Tool @('py.exe', 'py')
    if ($py) {
        return @{
            FilePath = $py
            Prefix = @('-3')
        }
    }

    throw 'Python 3 was not found on PATH.'
}

function Invoke-Native(
    [string]$FilePath,
    [string[]]$Arguments,
    [string]$Label,
    [string]$WorkingDirectory = $EmuleWorkspaceRoot,
    [switch]$AllowFailure,
    [hashtable]$EnvironmentOverrides
) {
    Push-Location $WorkingDirectory
    $originalEnv = @{}
    try {
        if ($EnvironmentOverrides) {
            foreach ($key in $EnvironmentOverrides.Keys) {
                $originalEnv[$key] = [Environment]::GetEnvironmentVariable($key)
                [Environment]::SetEnvironmentVariable($key, [string]$EnvironmentOverrides[$key])
            }
        }
        & $FilePath @Arguments
        $exitCode = $LASTEXITCODE
    } finally {
        if ($EnvironmentOverrides) {
            foreach ($key in $EnvironmentOverrides.Keys) {
                [Environment]::SetEnvironmentVariable($key, $originalEnv[$key])
            }
        }
        Pop-Location
    }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "$Label failed with exit code $exitCode."
    }
}

function Invoke-Git([string]$Repo, [string[]]$Arguments, [string]$Label, [switch]$AllowFailure) {
    $git = Resolve-Tool @('git.exe', 'git')
    if (-not $git) {
        throw 'git not found on PATH.'
    }
    $output = & $git -C $Repo @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "$Label failed with exit code $exitCode.`n$($output -join "`n")"
    }
    @($output)
}

function Get-RepoBranch([string]$Repo) {
    ((Invoke-Git $Repo @('rev-parse','--abbrev-ref','HEAD') 'git rev-parse') -join "`n").Trim()
}

function Get-RepoHead([string]$Repo) {
    ((Invoke-Git $Repo @('rev-parse','--short','HEAD') 'git rev-parse') -join "`n").Trim()
}

function Get-RepoStatus([string]$Repo) {
    @((Invoke-Git $Repo @('status','--short','--branch') 'git status') | Where-Object { $_ })
}

function Ensure-CanonicalAppAnchor {
    $canonicalRepoPath = Resolve-WorkspacePath $AppRepo.SeedRepo.Path
    if (-not (Test-Path -LiteralPath $canonicalRepoPath -PathType Container)) {
        throw "Canonical app repo is missing: $canonicalRepoPath"
    }

    $statusLines = @(Get-RepoStatus $canonicalRepoPath)
    if ($statusLines.Count -gt 1) {
        throw "Canonical app repo has local changes and cannot be re-anchored automatically: $canonicalRepoPath"
    }

    $expectedAnchorRevision = "refs/remotes/origin/{0}" -f $AppRepo.SeedRepo.Branch
    $expectedAnchorHead = ((Invoke-Git $canonicalRepoPath @('rev-parse', $expectedAnchorRevision) 'git rev-parse') -join "`n").Trim()
    $canonicalBranch = Get-RepoBranch $canonicalRepoPath
    $canonicalHead = ((Invoke-Git $canonicalRepoPath @('rev-parse', 'HEAD') 'git rev-parse') -join "`n").Trim()
    if ($canonicalBranch -eq 'HEAD' -and $canonicalHead -eq $expectedAnchorHead) {
        return
    }

    Write-Host ("Reanchoring canonical app repo to detached {0} at {1}" -f ("origin/{0}" -f $AppRepo.SeedRepo.Branch), $expectedAnchorHead)
    $null = Invoke-Git $canonicalRepoPath @('checkout', '--detach', $expectedAnchorRevision) 'git checkout --detach'
}

function Get-VsInfo {
    $vswhere = Resolve-Tool @('vswhere.exe', 'vswhere')
    if (-not $vswhere) {
        foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }) {
            $candidate = Join-Path $base 'Microsoft Visual Studio\Installer\vswhere.exe'
            if (Test-Path -LiteralPath $candidate) {
                $vswhere = $candidate
                break
            }
        }
    }

    $installPath = $null
    if ($vswhere) {
        $installPath = (& $vswhere -latest -products * -requires Microsoft.Component.MSBuild -property installationPath 2>$null | Select-Object -First 1).Trim()
    }

    if (-not $installPath) {
        foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }) {
            $root2022 = Join-Path $base 'Microsoft Visual Studio\2022'
            if (Test-Path -LiteralPath $root2022) {
                $installPath = (Get-ChildItem -LiteralPath $root2022 -Directory | Select-Object -First 1 -ExpandProperty FullName)
                if ($installPath) { break }
            }
        }
    }

    if (-not $installPath) {
        return $null
    }

    [pscustomobject]@{
        Root = $installPath
        MSBuild = Join-Path $installPath 'MSBuild\Current\Bin\MSBuild.exe'
    }
}

function Get-MSBuildPath {
    $vs = Get-VsInfo
    if (-not $vs -or -not (Test-Path -LiteralPath $vs.MSBuild)) {
        throw 'Visual Studio 2022 with MSBuild is required.'
    }
    $vs.MSBuild
}

<#
.SYNOPSIS
Resolves dumpbin.exe from the active Visual Studio toolchain.
#>
function Get-DumpbinPath {
    $cmd = Get-Command 'dumpbin.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
        return $cmd.Source
    }

    $vs = Get-VsInfo
    if (-not $vs) {
        throw 'Visual Studio 2022 with dumpbin.exe is required.'
    }

    $msvcRoot = Join-Path $vs.Root 'VC\Tools\MSVC'
    if (-not (Test-Path -LiteralPath $msvcRoot -PathType Container)) {
        throw "MSVC tools root not found: $msvcRoot"
    }

    $toolsets = @(Get-ChildItem -LiteralPath $msvcRoot -Directory | Sort-Object Name -Descending)
    foreach ($toolset in $toolsets) {
        foreach ($relativeCandidate in @(
            'bin\Hostx64\x64\dumpbin.exe',
            'bin\HostX64\x64\dumpbin.exe',
            'bin\Hostx64\arm64\dumpbin.exe',
            'bin\HostX64\arm64\dumpbin.exe'
        )) {
            $candidate = Join-Path $toolset.FullName $relativeCandidate
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                return $candidate
            }
        }
    }

    throw 'dumpbin.exe was not found in the active Visual Studio toolchain.'
}

function Get-CMakePath {
    $cmd = Get-Command 'cmake.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
        return $cmd.Source
    }

    $candidate = Join-Path ((Get-VsInfo).Root) 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
    if (-not (Test-Path -LiteralPath $candidate)) {
        throw 'cmake.exe not found.'
    }

    $candidate
}

function Get-PerlPath {
    $cmd = Get-Command 'perl.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) {
        return $cmd.Source
    }

    foreach ($candidate in @(
        'C:\Program Files\Git\usr\bin\perl.exe',
        'C:\Program Files (x86)\Git\usr\bin\perl.exe'
    )) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    throw 'perl.exe not found.'
}

function Invoke-MSBuildProject {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectPath,

        [Parameter(Mandatory = $true)]
        [string]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$Platform,

        [string[]]$ExtraProperties = @(),

        [ValidateSet('Build','Rebuild')]
        [string]$Target = 'Build',

        [hashtable]$EnvironmentOverrides,

        [string]$StepName = (Split-Path -LeafBase $ProjectPath)
    )

    $stepStartedAt = Get-Date
    $relativeProjectPath = [System.IO.Path]::GetRelativePath($EmuleWorkspaceRoot, $ProjectPath)
    $projectToken = Convert-ToFileToken ([System.IO.Path]::ChangeExtension($relativeProjectPath, $null))
    $logPath = Join-Path (Get-BuildLogDirectory) ("{0}-{1}-{2}-{3}.log" -f $projectToken, $Target.ToLowerInvariant(), $Configuration.ToLowerInvariant(), $Platform.ToLowerInvariant())
    $binaryLogPath = Join-Path (Get-BuildLogDirectory) ("{0}-{1}-{2}-{3}.binlog" -f $projectToken, $Target.ToLowerInvariant(), $Configuration.ToLowerInvariant(), $Platform.ToLowerInvariant())
    $argumentList = @(
        $ProjectPath,
        '/m',
        '/nologo',
        "/t:$Target",
        "/p:Configuration=$Configuration",
        "/p:Platform=$Platform",
        ("/flp:LogFile={0};Verbosity=normal;Encoding=UTF-8" -f $logPath),
        ("/bl:{0}" -f $binaryLogPath)
    ) + $ExtraProperties

    if ($BuildOutputMode -ne 'Full') {
        $argumentList += @(
            ("/clp:{0}" -f $(switch ($BuildOutputMode) {
                'Warnings' { 'WarningsOnly' }
                'ErrorsOnly' { 'ErrorsOnly' }
            }))
        )
    }

    try {
        Invoke-Native (Get-MSBuildPath) $argumentList "MSBuild $(Split-Path -Leaf $ProjectPath)" -EnvironmentOverrides $EnvironmentOverrides
        $durationSeconds = ((Get-Date) - $stepStartedAt).TotalSeconds
        $warningCount = Get-WarningCountFromLog -LogPath $logPath
        Add-BuildStepResult -StepName $StepName -Succeeded $true -LogPath $logPath -BinaryLogPath $binaryLogPath -DurationSeconds $durationSeconds -WarningCount $warningCount
        Write-BuildStepSummary -StepName $StepName -Succeeded $true -LogPath $logPath -DurationSeconds $durationSeconds
    } catch {
        $durationSeconds = ((Get-Date) - $stepStartedAt).TotalSeconds
        $warningCount = Get-WarningCountFromLog -LogPath $logPath
        Add-BuildStepResult -StepName $StepName -Succeeded $false -LogPath $logPath -BinaryLogPath $binaryLogPath -DurationSeconds $durationSeconds -WarningCount $warningCount
        Write-BuildStepSummary -StepName $StepName -Succeeded $false -LogPath $logPath -DurationSeconds $durationSeconds
        throw
    }
}

<#
.SYNOPSIS
Configures and builds a CMake dependency while publishing a standard build-step recap entry.
#>
function Invoke-CMakeDependencyBuild {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceDirectory,

        [Parameter(Mandatory = $true)]
        [string]$BuildDirectory,

        [Parameter(Mandatory = $true)]
        [string]$Configuration,

        [Parameter(Mandatory = $true)]
        [string]$Platform,

        [Parameter(Mandatory = $true)]
        [string]$StepName,

        [string]$TargetName = '',

        [string[]]$ConfigureArguments = @()
    )

    $stepStartedAt = Get-Date
    $relativeSourceDirectory = [System.IO.Path]::GetRelativePath($EmuleWorkspaceRoot, $SourceDirectory)
    $projectToken = Convert-ToFileToken ($relativeSourceDirectory + '-cmake')
    $logPath = Join-Path (Get-BuildLogDirectory) ("{0}-build-{1}-{2}.log" -f $projectToken, $Configuration.ToLowerInvariant(), $Platform.ToLowerInvariant())

    try {
        Ensure-Directory -Path $BuildDirectory
        if (Test-Path -LiteralPath $logPath) {
            Remove-Item -LiteralPath $logPath -Force
        }

        $cmakePath = Get-CMakePath
        $configureArgumentsList = @(
            '-S', $SourceDirectory,
            '-B', $BuildDirectory,
            '-G', 'Visual Studio 17 2022',
            '-A', $Platform,
            '-DBUILD_SHARED_LIBS=OFF'
        ) + $ConfigureArguments
        @(
            '== Configure ==',
            ("{0} {1}" -f $cmakePath, ($configureArgumentsList -join ' ')),
            ''
        ) | Set-Content -LiteralPath $logPath -Encoding utf8

        & $cmakePath $configureArgumentsList *>> $logPath
        if ($LASTEXITCODE -ne 0) {
            throw "cmake configure failed with exit code $LASTEXITCODE."
        }

        @(
            '',
            '== Build ==',
            "$cmakePath --build $BuildDirectory --config $Configuration"
        ) | Add-Content -LiteralPath $logPath -Encoding utf8

        $buildArguments = @(
            '--build', $BuildDirectory,
            '--config', $Configuration
        )
        if (-not [string]::IsNullOrWhiteSpace($TargetName)) {
            $buildArguments += @('--target', $TargetName)
        }

        & $cmakePath $buildArguments *>> $logPath
        if ($LASTEXITCODE -ne 0) {
            throw "cmake build failed with exit code $LASTEXITCODE."
        }

        $durationSeconds = ((Get-Date) - $stepStartedAt).TotalSeconds
        $warningCount = Get-WarningCountFromLog -LogPath $logPath
        Add-BuildStepResult -StepName $StepName -Succeeded $true -LogPath $logPath -BinaryLogPath '' -DurationSeconds $durationSeconds -WarningCount $warningCount
        Write-BuildStepSummary -StepName $StepName -Succeeded $true -LogPath $logPath -DurationSeconds $durationSeconds
    } catch {
        $durationSeconds = ((Get-Date) - $stepStartedAt).TotalSeconds
        $warningCount = Get-WarningCountFromLog -LogPath $logPath
        Add-BuildStepResult -StepName $StepName -Succeeded $false -LogPath $logPath -BinaryLogPath '' -DurationSeconds $durationSeconds -WarningCount $warningCount
        Write-BuildStepSummary -StepName $StepName -Succeeded $false -LogPath $logPath -DurationSeconds $durationSeconds
        throw
    }
}

<#
.SYNOPSIS
Returns the CMake arguments that align MSVC dependency builds with the app's static CRT policy.
#>
function Get-StaticMsvcRuntimeCMakeArguments {
    @(
        '-DCMAKE_POLICY_DEFAULT_CMP0091=NEW',
        '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug>'
    )
}

<#
.SYNOPSIS
Returns the built app binary path for a given app worktree/config/platform.
#>
function Get-AppBinaryPath([string]$AppRoot, [string]$Configuration, [string]$TargetPlatform) {
    Join-Path $AppRoot ("srchybrid\{0}\{1}\emule.exe" -f $TargetPlatform, $Configuration)
}

<#
.SYNOPSIS
Asserts that a resolved path stays inside an expected root before cleanup.
#>
function Assert-PathUnderRoot([string]$Path, [string]$Root, [string]$Label) {
    $resolvedPath = [System.IO.Path]::GetFullPath($Path)
    $resolvedRoot = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
    if (-not $resolvedPath.StartsWith($resolvedRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "$Label resolved outside expected root: $resolvedPath"
    }
}

function Copy-DirectoryContents([string]$SourcePath, [string]$DestinationPath) {
    Ensure-Directory $DestinationPath
    Copy-Item -Path (Join-Path $SourcePath '*') -Destination $DestinationPath -Recurse -Force
}

<#
.SYNOPSIS
Copies one release package file into a relative path under the package root.
#>
function Copy-PackageFile([string]$SourcePath, [string]$PackageRoot, [string]$RelativeDestinationPath) {
    if (-not (Test-Path -LiteralPath $SourcePath -PathType Leaf)) {
        throw "Cannot package missing file: $SourcePath"
    }

    $destinationPath = [System.IO.Path]::GetFullPath((Join-Path $PackageRoot $RelativeDestinationPath))
    Assert-PathUnderRoot -Path $destinationPath -Root $PackageRoot -Label 'release package file'
    Ensure-Directory (Split-Path -Parent $destinationPath)
    Copy-Item -LiteralPath $SourcePath -Destination $destinationPath -Force
}

<#
.SYNOPSIS
Writes the release package license notice that accompanies the GPL application binary.
#>
function New-PackageLicenseNotice([string]$PackageRoot) {
    $noticePath = [System.IO.Path]::GetFullPath((Join-Path $PackageRoot 'LICENSE-NOTICE.txt'))
    Assert-PathUnderRoot -Path $noticePath -Root $PackageRoot -Label 'release package license notice'
    @(
        'eMule broadband edition contains eMule-derived application code licensed under GPL-2.0-or-later.'
        'The source tree retains the per-file GPL notices from the original eMule project and eMule BB changes.'
        'Third-party libraries are linked from the canonical workspace dependency pins and retain their upstream licenses.'
        'For complete corresponding source, use the eMule BB source repositories at the app commit recorded in the package manifest.'
    ) | Set-Content -LiteralPath $noticePath -Encoding utf8
}

<#
.SYNOPSIS
Returns the active MSVC platform-toolset property used by release packaging helpers.
#>
function Get-DefaultPlatformToolsetProperty {
    $override = [Environment]::GetEnvironmentVariable($ToolsetOverrideVariable)
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        return "/p:PlatformToolset=$override"
    }

    '/p:PlatformToolset=v143'
}

<#
.SYNOPSIS
Builds the app language-resource solution for the selected package platform.
#>
function Build-LanguageResources([string]$AppRoot) {
    $languageSolution = Join-Path $AppRoot 'srchybrid\lang\lang.sln'
    if (-not (Test-Path -LiteralPath $languageSolution)) {
        throw "Cannot build missing language solution: $languageSolution"
    }

    $buildTarget = if ($Clean) { 'Rebuild' } else { 'Build' }
    Invoke-MSBuildProject -ProjectPath $languageSolution -Configuration Dynamic -Platform $Platform -ExtraProperties @(Get-DefaultPlatformToolsetProperty) -Target $buildTarget -StepName 'APP main language resources'
}

<#
.SYNOPSIS
Builds the main app binary used by release packaging for the selected package platform.
#>
function Build-PackageApp([string]$AppRoot) {
    $entry = Get-SelectedBuildTarget
    $project = Join-Path $AppRoot 'srchybrid\emule.vcxproj'
    $extraProperties = @(Get-AppPropertyOverrides -TargetPlatform $entry.Platform)
    $override = [Environment]::GetEnvironmentVariable($ToolsetOverrideVariable)
    if ($override) {
        $extraProperties += "/p:PlatformToolset=$override"
    }

    $buildTarget = if ($Clean) { 'Rebuild' } else { 'Build' }
    Ensure-AppDependencyArtifacts -Configuration $entry.Configuration -TargetPlatform $entry.Platform
    Invoke-MSBuildProject -ProjectPath $project -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties $extraProperties -Target $buildTarget -StepName 'APP main package binary'
    Verify-AppControlFlowGuard -BinaryPath (Get-AppBinaryPath -AppRoot $AppRoot -Configuration $entry.Configuration -TargetPlatform $entry.Platform) -StepName 'APP main package binary CFG'
}

<#
.SYNOPSIS
Resolves the built language DLL directory that is safe to copy into release packages.
#>
function Resolve-PackageLanguagePath([string]$AppRoot) {
    $langPath = Join-Path $AppRoot ("srchybrid\{0}\lang" -f $Platform)
    $langDll = if (Test-Path -LiteralPath $langPath -PathType Container) {
        Get-ChildItem -LiteralPath $langPath -File -Filter '*.dll' -ErrorAction SilentlyContinue | Select-Object -First 1
    } else {
        $null
    }

    if ($null -eq $langDll) {
        throw "Cannot package missing built language DLLs: $langPath"
    }

    $langPath
}

<#
.SYNOPSIS
Creates the documented eMule broadband edition release ZIP for one platform.
#>
function New-ReleasePackage {
    if ($Config -ne 'Release') {
        throw 'package-release requires -Config Release.'
    }
    if ($ReleaseVersion -notmatch '^\d+\.\d+\.\d+$') {
        throw "ReleaseVersion must use MAJOR.MINOR.PATCH format: $ReleaseVersion"
    }

    Ensure-CanonicalAppAnchor
    $appRoot = Resolve-AppVariantPath 'main' -RequireExists
    Build-PackageApp -AppRoot $appRoot
    Build-LanguageResources -AppRoot $appRoot
    $buildOutputRoot = [System.IO.Path]::GetFullPath((Join-Path $appRoot ("srchybrid\{0}\{1}" -f $Platform, $Config)))
    $exePath = Join-Path $buildOutputRoot 'emule.exe'
    $langPath = Resolve-PackageLanguagePath -AppRoot $appRoot
    $webserverPath = Join-Path $buildOutputRoot 'webserver'
    $webserverHasFiles = (Test-Path -LiteralPath $webserverPath -PathType Container) -and $null -ne (Get-ChildItem -LiteralPath $webserverPath -File -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $webserverHasFiles) {
        $webserverPath = Join-Path $appRoot 'srchybrid\webinterface'
    }
    foreach ($requiredPath in @($exePath, $langPath, $webserverPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Cannot package missing release runtime path: $requiredPath"
        }
    }

    $assetArch = if ($Platform -eq 'ARM64') { 'arm64' } else { 'x64' }
    $releaseRoot = [System.IO.Path]::GetFullPath((Join-Path (Get-WorkspaceStateRoot) ("release\emule-bb-v{0}" -f $ReleaseVersion)))
    $stagingRoot = [System.IO.Path]::GetFullPath((Join-Path $releaseRoot ("staging\{0}" -f $assetArch)))
    $packageRoot = [System.IO.Path]::GetFullPath((Join-Path $stagingRoot 'eMule'))
    $zipPath = [System.IO.Path]::GetFullPath((Join-Path $releaseRoot ("eMule-broadband-{0}-{1}.zip" -f $ReleaseVersion, $assetArch)))
    $manifestPath = [System.IO.Path]::GetFullPath((Join-Path $releaseRoot ("eMule-broadband-{0}-{1}.manifest.json" -f $ReleaseVersion, $assetArch)))

    foreach ($pathToCheck in @($stagingRoot, $packageRoot, $zipPath, $manifestPath)) {
        Assert-PathUnderRoot -Path $pathToCheck -Root $releaseRoot -Label 'release package path'
    }

    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force
    }
    Ensure-Directory $packageRoot
    Copy-Item -LiteralPath $exePath -Destination (Join-Path $packageRoot 'emule.exe')
    Copy-DirectoryContents -SourcePath $langPath -DestinationPath (Join-Path $packageRoot 'lang')
    Copy-DirectoryContents -SourcePath $webserverPath -DestinationPath (Join-Path $packageRoot 'webserver')
    Copy-PackageFile -SourcePath (Join-Path $appRoot 'README.md') -PackageRoot $packageRoot -RelativeDestinationPath 'README.md'
    New-PackageLicenseNotice -PackageRoot $packageRoot

    $toolingRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tooling
    Copy-PackageFile -SourcePath (Join-Path $toolingRepoRoot 'docs\rest\REST-API-CONTRACT.md') -PackageRoot $packageRoot -RelativeDestinationPath 'docs\REST-API-CONTRACT.md'
    Copy-PackageFile -SourcePath (Join-Path $toolingRepoRoot 'docs\rest\REST-API-OPENAPI.yaml') -PackageRoot $packageRoot -RelativeDestinationPath 'docs\REST-API-OPENAPI.yaml'
    Copy-PackageFile -SourcePath (Join-Path $toolingRepoRoot 'docs\rest\REST-API-PARITY-INVENTORY.md') -PackageRoot $packageRoot -RelativeDestinationPath 'docs\REST-API-PARITY-INVENTORY.md'

    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }
    Compress-Archive -LiteralPath $packageRoot -DestinationPath $zipPath -Force
    $zipHash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $exeHash = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $manifest = [ordered]@{
        product = 'eMule broadband edition'
        compactName = 'eMule BB'
        version = $ReleaseVersion
        tag = "emule-bb-v$ReleaseVersion"
        configuration = $Config
        platform = $Platform
        asset = [System.IO.Path]::GetFileName($zipPath)
        assetPath = $zipPath
        sha256 = $zipHash
        emuleExeSha256 = $exeHash
        appCommit = Get-RepoHead $appRoot
        generatedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        includedPaths = @(
            'eMule/emule.exe',
            'eMule/lang',
            'eMule/webserver',
            'eMule/README.md',
            'eMule/LICENSE-NOTICE.txt',
            'eMule/docs/REST-API-CONTRACT.md',
            'eMule/docs/REST-API-OPENAPI.yaml',
            'eMule/docs/REST-API-PARITY-INVENTORY.md'
        )
    }
    $manifest | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $manifestPath -Encoding utf8
    Write-Host "Release package: $zipPath"
    Write-Host "Release manifest: $manifestPath"
    Write-Host "SHA256: $zipHash"
}

<#
.SYNOPSIS
Verifies that the built app binary contains Control Flow Guard metadata.
#>
function Verify-AppControlFlowGuard {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BinaryPath,

        [string]$StepName = 'APP main CFG'
    )

    $stepStartedAt = Get-Date
    $relativeBinaryPath = [System.IO.Path]::GetRelativePath($EmuleWorkspaceRoot, $BinaryPath)
    $logPath = Join-Path (Get-BuildLogDirectory) ("{0}-cfg.log" -f (Convert-ToFileToken ([System.IO.Path]::ChangeExtension($relativeBinaryPath, $null))))

    try {
        if (-not (Test-Path -LiteralPath $BinaryPath -PathType Leaf)) {
            throw "Built app binary not found: $BinaryPath"
        }

        $dumpbin = Get-DumpbinPath
        $output = @(& $dumpbin /headers /loadconfig $BinaryPath 2>&1)
        $exitCode = $LASTEXITCODE
        $output | Set-Content -LiteralPath $logPath -Encoding utf8
        if ($exitCode -ne 0) {
            throw "dumpbin failed with exit code $exitCode for $BinaryPath"
        }

        $text = $output -join "`n"
        foreach ($pattern in @('CF Instrumented', 'FID table present')) {
            if ($text -notmatch [regex]::Escape($pattern)) {
                throw "CFG verification failed for ${BinaryPath}: missing '$pattern' in dumpbin output."
            }
        }

        $durationSeconds = ((Get-Date) - $stepStartedAt).TotalSeconds
        Add-BuildStepResult -StepName $StepName -Succeeded $true -LogPath $logPath -BinaryLogPath '' -DurationSeconds $durationSeconds -WarningCount 0
        Write-BuildStepSummary -StepName $StepName -Succeeded $true -LogPath $logPath -DurationSeconds $durationSeconds
    } catch {
        $durationSeconds = ((Get-Date) - $stepStartedAt).TotalSeconds
        Add-BuildStepResult -StepName $StepName -Succeeded $false -LogPath $logPath -BinaryLogPath '' -DurationSeconds $durationSeconds -WarningCount 0
        Write-BuildStepSummary -StepName $StepName -Succeeded $false -LogPath $logPath -DurationSeconds $durationSeconds
        throw
    }
}

function Get-SelectedBuildTarget {
    [pscustomobject]@{
        Configuration = $Config
        Platform = $Platform
    }
}

function Assert-TestExecutionPlatformSupported {
    if ($Platform -ne 'x64') {
        throw "Shared test execution currently supports x64 only. Requested platform: $Platform"
    }
}

function Get-TestBuildTag([string]$WorkspaceRoot, [string]$AppRoot) {
    $workspaceLeaf = Split-Path -Leaf $WorkspaceRoot
    $workspacesRoot = Split-Path -Parent $WorkspaceRoot
    $workspaceOwner = if ($workspacesRoot) { Split-Path -Leaf (Split-Path -Parent $workspacesRoot) } else { '' }
    $segments = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrWhiteSpace($workspaceOwner)) {
        $segments.Add($workspaceOwner) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($workspaceLeaf)) {
        $segments.Add($workspaceLeaf) | Out-Null
    }
    if (-not [string]::IsNullOrWhiteSpace($AppRoot)) {
        $segments.Add((Split-Path -Leaf $AppRoot)) | Out-Null
    }
    (($segments -join '-') -replace '[^A-Za-z0-9._-]', '_')
}

function Get-AppVariants {
    $apps = [System.Collections.Generic.List[object]]::new()
    foreach ($variant in $AppRepo.Variants) {
        $path = Resolve-WorkspacePath $variant.Path
        $apps.Add([pscustomobject]@{
            Name = $variant.Name
            Branch = $variant.Branch
            Path = $path
            Exists = Test-Path -LiteralPath $path
            CurrentBranch = if (Test-Path -LiteralPath $path) { Get-RepoBranch $path } else { $null }
        }) | Out-Null
    }
    $apps
}

function Get-ActiveApps {
    $apps = @(Get-AppVariants | Where-Object { $_.Exists })
    if ($null -eq $AppVariant -or $AppVariant.Count -eq 0) {
        return $apps
    }

    $selectedNames = @($AppVariant | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() } | Select-Object -Unique)
    if ($selectedNames.Count -eq 0) {
        return $apps
    }

    $selectedApps = @($apps | Where-Object { $_.Name -in $selectedNames })
    $selectedAppNames = @($selectedApps | ForEach-Object { $_.Name })
    $missingVariants = @($selectedNames | Where-Object { $_ -notin $selectedAppNames })
    if ($missingVariants.Count -gt 0) {
        throw ("Unknown or unavailable app variant(s): {0}" -f ($missingVariants -join ', '))
    }

    $selectedApps
}

function Get-AppVariant([string]$Name) {
    $variant = @(Get-AppVariants | Where-Object { $_.Name -eq $Name } | Select-Object -First 1)[0]
    if ($null -eq $variant) {
        throw "App variant '$Name' is not defined in deps.psd1."
    }
    $variant
}

function Resolve-AppVariantPath([string]$Name, [switch]$RequireExists) {
    $variant = Get-AppVariant $Name
    if ($RequireExists -and -not $variant.Exists) {
        throw "App variant '$Name' is missing: $($variant.Path)"
    }
    $variant.Path
}

function Test-AppBranchAllowed([string]$ExpectedBranch, [string]$CurrentBranch) {
    if ($CurrentBranch -eq $ExpectedBranch) {
        return $true
    }

    if ($ExpectedBranch -eq 'main' -and $CurrentBranch -match '^(feature|fix|chore)/') {
        return $true
    }

    $false
}

function Assert-AppLayout {
    $missing = @(Get-AppVariants | Where-Object { -not $_.Exists })
    if ($missing.Count -gt 0) {
        throw ("Missing app worktrees:`n{0}" -f (($missing | ForEach-Object { $_.Path }) -join [Environment]::NewLine))
    }

    foreach ($app in Get-AppVariants) {
        if (-not (Test-AppBranchAllowed -ExpectedBranch $app.Branch -CurrentBranch $app.CurrentBranch)) {
            throw "App checkout '$($app.Path)' is on branch '$($app.CurrentBranch)', expected '$($app.Branch)'."
        }
    }
}

function Assert-RequiredWorkspacePaths {
    $requiredPaths = [System.Collections.Generic.List[string]]::new()
    $requiredPaths.Add($EmuleWorkspaceRoot) | Out-Null
    $requiredPaths.Add((Get-WorkspaceRoot)) | Out-Null
    $requiredPaths.Add((Resolve-WorkspacePath $AppRepo.SeedRepo.Path)) | Out-Null
    $requiredPaths.Add((Resolve-WorkspacePath $Workspace.Repos.Tests)) | Out-Null
    foreach ($dependency in $Dependencies) {
        $requiredPaths.Add((Resolve-WorkspacePath $dependency.Path)) | Out-Null
    }
    foreach ($app in Get-AppVariants) {
        $requiredPaths.Add($app.Path) | Out-Null
    }

    $missing = @($requiredPaths | Where-Object { -not (Test-Path -LiteralPath $_) } | Select-Object -Unique)
    if ($missing.Count -gt 0) {
        throw ("Missing required workspace paths:`n{0}" -f ($missing -join [Environment]::NewLine))
    }
}

function Get-MbedTlsProjectPath {
    Join-Path (Resolve-WorkspacePath 'repos\third_party\eMule-mbedtls') 'visualc\VS2017\mbedTLS.vcxproj'
}

function Get-MbedTlsLibraryRoot([string]$TargetPlatform) {
    $path = Join-Path (Resolve-WorkspacePath 'repos\third_party\eMule-mbedtls') ("visualc\VS2017-{0}\library" -f $TargetPlatform)
    if (-not $path.EndsWith('\')) {
        $path += '\'
    }
    $path
}

<#
.SYNOPSIS
Returns the canonical CMake build root for the libpcpnatpmp dependency.
#>
function Get-LibPcpNatPmpBuildRoot([string]$TargetPlatform) {
    Join-Path (Resolve-WorkspacePath 'repos\third_party\eMule-libpcpnatpmp') ("cmake-build-{0}" -f $TargetPlatform.ToLowerInvariant())
}

<#
.SYNOPSIS
Returns the static-library path produced for libpcpnatpmp for a given configuration and platform.
#>
function Get-LibPcpNatPmpLibraryPath([string]$Configuration, [string]$TargetPlatform) {
    Join-Path (Get-LibPcpNatPmpBuildRoot -TargetPlatform $TargetPlatform) ("lib\{0}\pcpnatpmp.lib" -f $Configuration)
}

function Get-AppPropertyOverrides([string]$TargetPlatform) {
    @(
        "/p:WorkspaceRoot=$EmuleWorkspaceRoot\"
        "/p:CryptoPpRoot=$(Resolve-WorkspacePath 'repos\third_party\eMule-cryptopp')\"
        "/p:Id3libRoot=$(Resolve-WorkspacePath 'repos\third_party\eMule-id3lib')\"
        "/p:MbedTlsRoot=$(Resolve-WorkspacePath 'repos\third_party\eMule-mbedtls')\"
        "/p:MbedTlsLibRoot=$(Get-MbedTlsLibraryRoot -TargetPlatform $TargetPlatform)"
        "/p:MiniUpnpRoot=$(Resolve-WorkspacePath 'repos\third_party\eMule-miniupnp')\"
        "/p:NlohmannJsonRoot=$(Resolve-WorkspacePath 'repos\third_party\eMule-nlohmann-json\single_include')\"
        "/p:PcpNatPmpRoot=$(Resolve-WorkspacePath 'repos\third_party\eMule-libpcpnatpmp')\"
        "/p:PcpNatPmpLibRoot=$(Join-Path (Get-LibPcpNatPmpBuildRoot -TargetPlatform $TargetPlatform) 'lib')\"
        "/p:ResizableLibRoot=$(Resolve-WorkspacePath 'repos\third_party\eMule-ResizableLib')\"
        "/p:ZlibRoot=$(Resolve-WorkspacePath 'repos\third_party\eMule-zlib')\"
    )
}

function Get-AppDependencyArtifacts([string]$Configuration, [string]$TargetPlatform) {
    $thirdPartyRoot = Resolve-WorkspacePath 'repos\third_party'
    @(
        [pscustomobject]@{
            Name = 'cryptopp'
            Path = Join-Path $thirdPartyRoot ("eMule-cryptopp\{0}\Output\{1}\cryptlib.lib" -f $TargetPlatform, $Configuration)
        }
        [pscustomobject]@{
            Name = 'id3lib'
            Path = Join-Path $thirdPartyRoot ("eMule-id3lib\libprj\{0}\{1}\id3lib.lib" -f $TargetPlatform, $Configuration)
        }
        [pscustomobject]@{
            Name = 'miniupnp'
            Path = Join-Path $thirdPartyRoot ("eMule-miniupnp\miniupnpc\msvc\{0}\{1}\miniupnpc.lib" -f $TargetPlatform, $Configuration)
        }
        [pscustomobject]@{
            Name = 'libpcpnatpmp'
            Path = Get-LibPcpNatPmpLibraryPath -Configuration $Configuration -TargetPlatform $TargetPlatform
        }
        [pscustomobject]@{
            Name = 'ResizableLib'
            Path = Join-Path $thirdPartyRoot ("eMule-ResizableLib\ResizableLib\{0}\{1}\ResizableLib.lib" -f $TargetPlatform, $Configuration)
        }
        [pscustomobject]@{
            Name = 'zlib'
            Path = Join-Path $thirdPartyRoot ("eMule-zlib\contrib\vstudio\vc\{0}\{1}\zlib.lib" -f $TargetPlatform, $Configuration)
        }
        [pscustomobject]@{
            Name = 'mbedtls'
            Path = Join-Path (Get-MbedTlsLibraryRoot -TargetPlatform $TargetPlatform) ("{0}\mbedtls.lib" -f $Configuration)
        }
        [pscustomobject]@{
            Name = 'mbedx509'
            Path = Join-Path (Get-MbedTlsLibraryRoot -TargetPlatform $TargetPlatform) ("{0}\mbedx509.lib" -f $Configuration)
        }
        [pscustomobject]@{
            Name = 'tfpsacrypto'
            Path = Join-Path (Split-Path -Parent (Get-MbedTlsLibraryRoot -TargetPlatform $TargetPlatform)) ("tf-psa-crypto\core\{0}\tfpsacrypto.lib" -f $Configuration)
        }
    )
}

function Get-MissingAppDependencyArtifacts([string]$Configuration, [string]$TargetPlatform) {
    @(Get-AppDependencyArtifacts -Configuration $Configuration -TargetPlatform $TargetPlatform | Where-Object { -not (Test-Path -LiteralPath $_.Path) })
}

function Ensure-AppDependencyArtifacts([string]$Configuration, [string]$TargetPlatform) {
    $missing = @(Get-MissingAppDependencyArtifacts -Configuration $Configuration -TargetPlatform $TargetPlatform)
    if ($missing.Count -eq 0) {
        return
    }

    Write-Host ("Missing dependency outputs for {0}|{1}; running build-libs." -f $Configuration, $TargetPlatform) -ForegroundColor Yellow
    Build-Libs

    $missing = @(Get-MissingAppDependencyArtifacts -Configuration $Configuration -TargetPlatform $TargetPlatform)
    if ($missing.Count -gt 0) {
        $details = ($missing | ForEach-Object { "{0}: {1}" -f $_.Name, $_.Path }) -join [Environment]::NewLine
        throw "Required dependency outputs are still missing for ${Configuration}|${TargetPlatform}:`n$details"
    }
}

function Get-CryptoPpPlatformPropertyOverrides([string]$TargetPlatform) {
    $properties = @()
    $override = [Environment]::GetEnvironmentVariable($ToolsetOverrideVariable)
    if (-not [string]::IsNullOrWhiteSpace($override)) {
        $properties += "/p:PlatformToolset=$override"
    } else {
        $properties += '/p:PlatformToolset=v143'
    }

    if ($TargetPlatform -eq 'ARM64') {
        $properties += @(
            "/p:ForceImportAfterCppProps=$(Get-Arm64OverridesPropsPath)",
            "/p:ForceImportAfterCppTargets=$(Get-Arm64OverridesTargetsPath)"
        )
    }

    $properties
}

function Get-Arm64OverridesPropsPath {
    Join-Path (Get-WorkspaceStateRoot) 'arm64-build-overrides.props'
}

function Get-Arm64OverridesTargetsPath {
    Join-Path (Get-WorkspaceStateRoot) 'arm64-build-overrides.targets'
}

function Ensure-Arm64OverridesTargets {
    Ensure-Directory -Path (Get-WorkspaceStateRoot)
    $propsPath = Get-Arm64OverridesPropsPath
    $targetsPath = Get-Arm64OverridesTargetsPath
    $propsContent = @'
<Project ToolsVersion="Current" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemDefinitionGroup Condition="'$(Platform)'=='ARM64'">
    <ClCompile>
      <AdditionalOptions>/DCRYPTOPP_DISABLE_ASM /DCRYPTOPP_NO_CPU_FEATURE_PROBES %(AdditionalOptions)</AdditionalOptions>
    </ClCompile>
  </ItemDefinitionGroup>
</Project>
'@
    $targetsContent = @'
<Project ToolsVersion="Current" xmlns="http://schemas.microsoft.com/developer/msbuild/2003">
  <ItemGroup Condition="'$(Platform)'=='ARM64'">
    <ClCompile Remove="blake2s_simd.cpp;blake2b_simd.cpp;chacha_simd.cpp;crc_simd.cpp;gcm_simd.cpp;gf2n_simd.cpp;lea_simd.cpp;rijndael_simd.cpp;sha_simd.cpp;simon128_simd.cpp;speck128_simd.cpp" />
  </ItemGroup>
</Project>
'@
    Set-Content -LiteralPath $propsPath -Value $propsContent -Encoding utf8
    Set-Content -LiteralPath $targetsPath -Value $targetsContent -Encoding utf8
}

function Get-Id3libPropertyOverrides([string]$Configuration, [string]$TargetPlatform) {
    if ($Configuration -eq 'Release' -and $TargetPlatform -eq 'ARM64') {
        return @(
            '/p:PlatformToolset=v143',
            '/p:ConfigurationType=StaticLibrary'
        )
    }

    @()
}

function Get-CryptoPpEnvironmentOverrides([string]$TargetPlatform) {
    if ($TargetPlatform -ne 'ARM64') {
        return @{}
    }

    @{
        CL = '/DCRYPTOPP_DISABLE_ASM /DCRYPTOPP_NO_CPU_FEATURE_PROBES'
    }
}

function Remove-StaleGeneratedArtifacts([string]$RepoPath, [ValidateSet('zlib', 'mbedtls')][string]$Kind) {
    $paths = switch ($Kind) {
        'zlib' { @((Join-Path $RepoPath 'cmake-build-x64')) }
        'mbedtls' { @((Join-Path $RepoPath 'visualc\VS2017-x64'), (Join-Path $RepoPath 'visualc\VS2017\x64')) }
    }

    foreach ($path in $paths) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Recurse -Force
        }
    }
}

function Build-Libs {
    $thirdPartyRoot = Resolve-WorkspacePath 'repos\third_party'
    $cmakePath = Get-CMakePath
    $perlPath = Get-PerlPath

    $entry = Get-SelectedBuildTarget
    $buildTarget = if ($Clean) { 'Rebuild' } else { 'Build' }
    if ($entry.Platform -eq 'ARM64') {
        Ensure-Arm64OverridesTargets
    }

    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-cryptopp\cryptlib.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties (Get-CryptoPpPlatformPropertyOverrides $entry.Platform) -EnvironmentOverrides (Get-CryptoPpEnvironmentOverrides $entry.Platform) -Target $buildTarget -StepName 'DEP cryptopp'
    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-id3lib\libprj\id3lib.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties (Get-Id3libPropertyOverrides $entry.Configuration $entry.Platform) -Target $buildTarget -StepName 'DEP id3lib'
    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-miniupnp\miniupnpc\msvc\miniupnpc.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -Target $buildTarget -StepName 'DEP miniupnp'
    if ($Clean) {
        $libPcpNatPmpBuildRoot = Get-LibPcpNatPmpBuildRoot -TargetPlatform $entry.Platform
        if (Test-Path -LiteralPath $libPcpNatPmpBuildRoot) {
            Remove-Item -LiteralPath $libPcpNatPmpBuildRoot -Recurse -Force
        }
    }
    Invoke-CMakeDependencyBuild -SourceDirectory (Join-Path $thirdPartyRoot 'eMule-libpcpnatpmp') -BuildDirectory (Get-LibPcpNatPmpBuildRoot -TargetPlatform $entry.Platform) -Configuration $entry.Configuration -Platform $entry.Platform -TargetName 'pcpnatpmp' -StepName 'DEP libpcpnatpmp' -ConfigureArguments (Get-StaticMsvcRuntimeCMakeArguments)
    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-ResizableLib\ResizableLib\ResizableLib.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -Target $buildTarget -StepName 'DEP ResizableLib'

    if ($Clean -and $entry.Configuration -eq 'Debug' -and $entry.Platform -eq 'x64') {
        Remove-StaleGeneratedArtifacts -RepoPath (Join-Path $thirdPartyRoot 'eMule-zlib') -Kind 'zlib'
        Remove-StaleGeneratedArtifacts -RepoPath (Join-Path $thirdPartyRoot 'eMule-mbedtls') -Kind 'mbedtls'
    }

    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-zlib\contrib\vstudio\vc\zlib.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties @("/p:WorkspaceCMakeExe=$cmakePath") -Target $buildTarget -StepName 'DEP zlib'
    Invoke-MSBuildProject -ProjectPath (Get-MbedTlsProjectPath) -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties @("/p:WorkspaceCMakeExe=$cmakePath", "/p:WorkspacePerlExe=$perlPath") -Target $buildTarget -StepName 'DEP mbedtls'
}

function Build-Apps {
    Assert-AppLayout
    $entry = Get-SelectedBuildTarget
    $appProperties = Get-AppPropertyOverrides -TargetPlatform $entry.Platform
    $buildTarget = if ($Clean) { 'Rebuild' } else { 'Build' }
    Ensure-AppDependencyArtifacts -Configuration $entry.Configuration -TargetPlatform $entry.Platform
    foreach ($app in Get-ActiveApps) {
        $project = Join-Path $app.Path 'srchybrid\emule.vcxproj'
        $extraProperties = @($appProperties)
        $override = [Environment]::GetEnvironmentVariable($ToolsetOverrideVariable)
        if ($override) {
            $extraProperties += "/p:PlatformToolset=$override"
        }
        Invoke-MSBuildProject -ProjectPath $project -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties $extraProperties -Target $buildTarget -StepName ("APP {0}" -f $app.Name)
        if ($app.Name -eq 'main') {
            Verify-AppControlFlowGuard -BinaryPath (Get-AppBinaryPath -AppRoot $app.Path -Configuration $entry.Configuration -TargetPlatform $entry.Platform) -StepName ("APP {0} CFG" -f $app.Name)
        }
    }
}

function Build-Tests {
    $testRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tests
    $workspaceRoot = Get-WorkspaceRoot
    $testBuildVariant = if ([string]::IsNullOrWhiteSpace($TestRunVariant)) { $TestTargets.TestBuildVariant } else { $TestRunVariant }
    $appRoot = Resolve-AppVariantPath -Name $testBuildVariant -RequireExists
    $scriptPath = Join-Path $testRepoRoot 'scripts\build-emule-tests.py'
    $entry = Get-SelectedBuildTarget
    $buildTag = Get-TestBuildTag -WorkspaceRoot $workspaceRoot -AppRoot $appRoot
    $logPath = Join-Path (Get-BuildLogDirectory) ("{0}-{1}-{2}.log" -f (Convert-ToFileToken ("emule-tests-{0}" -f $buildTag)), $entry.Configuration.ToLowerInvariant(), $entry.Platform.ToLowerInvariant())
    $binaryLogPath = Join-Path (Get-BuildLogDirectory) ("{0}-{1}-{2}.binlog" -f (Convert-ToFileToken ("emule-tests-{0}" -f $buildTag)), $entry.Configuration.ToLowerInvariant(), $entry.Platform.ToLowerInvariant())
    $stepStartedAt = Get-Date
    $pythonInvocation = Get-PythonInvocation

    try {
        $buildTestArguments = @(
            $pythonInvocation.Prefix
            $scriptPath,
            '--test-repo-root',
            $testRepoRoot,
            '--workspace-root',
            $workspaceRoot,
            '--app-root',
            $appRoot,
            '--configuration',
            $entry.Configuration,
            '--platform',
            $entry.Platform,
            '--build-output-mode',
            $BuildOutputMode,
            '--build-log-session-stamp',
            (Get-BuildLogSessionStamp)
        )
        if ($Clean) {
            $buildTestArguments += '--clean'
        }
        Invoke-Native $pythonInvocation.FilePath $buildTestArguments "build-emule-tests $($entry.Configuration)/$($entry.Platform)"
        $durationSeconds = ((Get-Date) - $stepStartedAt).TotalSeconds
        $warningCount = Get-WarningCountFromLog -LogPath $logPath
        Add-BuildStepResult -StepName 'TEST emule-tests' -Succeeded $true -LogPath $logPath -BinaryLogPath $binaryLogPath -DurationSeconds $durationSeconds -WarningCount $warningCount
    } catch {
        $durationSeconds = ((Get-Date) - $stepStartedAt).TotalSeconds
        $warningCount = Get-WarningCountFromLog -LogPath $logPath
        Add-BuildStepResult -StepName 'TEST emule-tests' -Succeeded $false -LogPath $logPath -BinaryLogPath $binaryLogPath -DurationSeconds $durationSeconds -WarningCount $warningCount
        throw
    }
}

function Invoke-LiveDiffRuns {
    param(
        [string]$TestRunVariantName = $TestTargets.TestRunVariant,
        [string]$BaselineVariantName = $TestTargets.BaselineVariant
    )

    Assert-TestExecutionPlatformSupported
    $testRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tests
    $workspaceRoot = Get-WorkspaceRoot
    $testRunAppRoot = Resolve-AppVariantPath -Name $TestRunVariantName -RequireExists
    $baselineAppRoot = Resolve-AppVariantPath -Name $BaselineVariantName -RequireExists
    $entry = Get-SelectedBuildTarget
    $liveDiffScriptPath = Join-Path $testRepoRoot 'scripts\run-live-diff.py'
    $pythonInvocation = Get-PythonInvocation

    Invoke-Native $pythonInvocation.FilePath @($pythonInvocation.Prefix + @(
        $liveDiffScriptPath,
        '--test-repo-root',
        $testRepoRoot,
        '--test-run-workspace-root',
        $workspaceRoot,
        '--test-run-app-root',
        $testRunAppRoot,
        '--baseline-workspace-root',
        $workspaceRoot,
        '--baseline-app-root',
        $baselineAppRoot,
        '--configuration',
        $entry.Configuration,
        '--platform',
        $entry.Platform
    )) ("live diff {0} vs {1}" -f $TestRunVariantName, $BaselineVariantName)
}

function Invoke-CommunityCoreCoverage {
    param(
        [string]$TestRunVariantName = $TestTargets.TestRunVariant,
        [string]$BaselineVariantName = $TestTargets.BaselineVariant
    )

    Assert-TestExecutionPlatformSupported
    $testRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tests
    $workspaceRoot = Get-WorkspaceRoot
    $testRunAppRoot = Resolve-AppVariantPath -Name $TestRunVariantName -RequireExists
    $baselineAppRoot = Resolve-AppVariantPath -Name $BaselineVariantName -RequireExists
    $entry = Get-SelectedBuildTarget
    $communityCoreCoverageScriptPath = Join-Path $testRepoRoot 'scripts\run-community-core-coverage.py'
    $pythonInvocation = Get-PythonInvocation

    Invoke-Native $pythonInvocation.FilePath @($pythonInvocation.Prefix + @(
        $communityCoreCoverageScriptPath,
        '--test-repo-root',
        $testRepoRoot,
        '--workspace-root',
        $workspaceRoot,
        '--main-app-root',
        $testRunAppRoot,
        '--community-app-root',
        $baselineAppRoot,
        '--configuration',
        $entry.Configuration,
        '--platform',
        $entry.Platform,
        '--include-live-rest-e2e',
        '--rest-coverage-budget',
        $RestCoverageBudget,
        '--rest-stress-budget',
        $RestStressBudget
    )) ("community core coverage {0} vs {1}" -f $TestRunVariantName, $BaselineVariantName)
}

function Invoke-TestRuns {
    Assert-TestExecutionPlatformSupported
    $testRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tests
    $workspaceRoot = Get-WorkspaceRoot
    $testRunAppRoot = Resolve-AppVariantPath -Name $TestTargets.TestRunVariant -RequireExists
    $buildTag = Get-TestBuildTag -WorkspaceRoot $workspaceRoot -AppRoot $testRunAppRoot
    $entry = Get-SelectedBuildTarget

    $coverageScriptPath = Join-Path $testRepoRoot 'scripts\run-native-coverage.py'
    $pythonInvocation = Get-PythonInvocation
    $nativeTestSuites = @('parity', 'web_api')

    $binaryPath = Join-Path $testRepoRoot ("build\{0}\{1}\{2}\emule-tests.exe" -f $buildTag, $entry.Platform, $entry.Configuration)
    if (-not (Test-Path -LiteralPath $binaryPath)) {
        throw "Built test executable not found: $binaryPath"
    }
    foreach ($suiteName in $nativeTestSuites) {
        Invoke-Native $binaryPath @("--test-suite=$suiteName") "$suiteName tests $($entry.Configuration)/$($entry.Platform)" $testRepoRoot
    }

    Invoke-Native $pythonInvocation.FilePath @($pythonInvocation.Prefix + @(
        $coverageScriptPath,
        '--test-repo-root',
        $testRepoRoot,
        '--workspace-root',
        $workspaceRoot,
        '--app-root',
        $testRunAppRoot,
        '--configuration',
        $entry.Configuration,
        '--platform',
        $entry.Platform,
        '--suite-name',
        'parity',
        '--suite-name',
        'web_api'
    )) 'native coverage'

    Invoke-LiveDiffRuns -TestRunVariantName $TestTargets.TestRunVariant -BaselineVariantName $TestTargets.BaselineVariant
}

function Invoke-PythonTestRuns {
    $testRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tests
    $pythonInvocation = Get-PythonInvocation
    $pytestArguments = @()
    if ($PythonTestQuiet) {
        $pytestArguments += '-q'
    }
    $pytestArguments += @($PythonTestPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (-not [string]::IsNullOrWhiteSpace($PythonTestExpression)) {
        $pytestArguments += @('-k', $PythonTestExpression)
    }
    $pytestArguments += @($PythonTestArgs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $arguments = @($pythonInvocation.Prefix + @('-m', 'pytest') + $pytestArguments)

    Invoke-Native $pythonInvocation.FilePath $arguments 'python tests' $testRepoRoot
}

function Invoke-LiveE2eSuite {
    Assert-TestExecutionPlatformSupported
    $testRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tests
    $workspaceRoot = Get-WorkspaceRoot
    $appRoot = Resolve-AppVariantPath -Name $TestTargets.TestRunVariant -RequireExists
    $entry = Get-SelectedBuildTarget
    $liveE2eScriptPath = Join-Path $testRepoRoot 'scripts\run-live-e2e-suite.py'
    if (-not (Test-Path -LiteralPath $liveE2eScriptPath -PathType Leaf)) {
        throw "Missing live E2E suite runner: $liveE2eScriptPath"
    }

    $pythonInvocation = Get-PythonInvocation
    $arguments = @(
        $pythonInvocation.Prefix
        $liveE2eScriptPath
        '--workspace-root'
        $workspaceRoot
        '--app-root'
        $appRoot
        '--configuration'
        $entry.Configuration
        '--startup-trace-mode'
        $StartupTraceMode
        '--rest-server-search-count'
        $RestServerSearchCount
        '--rest-kad-search-count'
        $RestKadSearchCount
        '--rest-download-trigger-count'
        $RestDownloadTriggerCount
        '--rest-coverage-budget'
        $RestCoverageBudget
        '--rest-stress-budget'
        $RestStressBudget
        '--rest-stress-duration-seconds'
        $RestStressDurationSeconds
        '--rest-stress-concurrency'
        $RestStressConcurrency
        '--rest-stress-max-failures'
        $RestStressMaxFailures
        '--rest-stress-request-timeout-seconds'
        $RestStressRequestTimeoutSeconds
        '--rest-socket-adversity-budget'
        $RestSocketAdversityBudget
        '--rest-tls-handshake-adversity-budget'
        $RestTlsHandshakeAdversityBudget
        '--rest-leak-churn-budget'
        $RestLeakChurnBudget
        '--p2p-bind-interface-name'
        $P2PBindInterfaceName
        '--rest-cold-start-dump-stress-waves'
        $RestColdStartDumpStressWaves
        '--rest-cold-start-dump-stress-searches-per-wave'
        $RestColdStartDumpStressSearchesPerWave
        '--rest-cold-start-dump-stress-max-concurrent-searches'
        $RestColdStartDumpStressMaxConcurrentSearches
        '--rest-cold-start-dump-stress-downloads-per-wave'
        $RestColdStartDumpStressDownloadsPerWave
        '--rest-cold-start-dump-stress-post-drain-seconds'
        $RestColdStartDumpStressPostDrainSeconds
        '--rest-cold-start-dump-stress-tool-timeout-seconds'
        $RestColdStartDumpStressToolTimeoutSeconds
    )

    if ($RestColdStartDumpStressEnableUmdh) {
        $arguments += '--rest-cold-start-dump-stress-enable-umdh'
    }
    if ($RestColdStartDumpStressSkipDumps) {
        $arguments += '--rest-cold-start-dump-stress-skip-dumps'
    }
    if ($RestLeakChurnCycles -ge 0) {
        $arguments += @('--rest-leak-churn-cycles', $RestLeakChurnCycles)
    }
    if ($RestStopStartAfterChurn) {
        $arguments += '--rest-stop-start-after-churn'
    }
    if (-not [string]::IsNullOrWhiteSpace($SharedRoot)) {
        $arguments += @('--shared-root', $SharedRoot)
    }
    if ($SharedFilesTreeStressChurnCycles -ge 0) {
        $arguments += @('--shared-files-tree-stress-churn-cycles', $SharedFilesTreeStressChurnCycles)
    }
    if (-not [string]::IsNullOrWhiteSpace($RestSearchMethodOverride)) {
        $arguments += @('--rest-search-method-override', $RestSearchMethodOverride)
    }
    $arguments += @('--rest-webserver-scheme', $RestWebServerScheme)
    foreach ($suiteName in @($LiveSuite | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        $arguments += @('--suite', $suiteName)
    }
    if ($LiveFailFast) {
        $arguments += '--fail-fast'
    }
    if ($SkipLiveSeedRefresh) {
        $arguments += '--skip-live-seed-refresh'
    }
    Invoke-Native $pythonInvocation.FilePath $arguments 'live E2E suite'
}

function Invoke-AmutorrentInteractiveSession {
    Assert-TestExecutionPlatformSupported
    $testRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tests
    $workspaceRoot = Get-WorkspaceRoot
    $appRoot = Resolve-AppVariantPath -Name $TestTargets.TestRunVariant -RequireExists
    $entry = Get-SelectedBuildTarget
    $sessionScriptPath = Join-Path $testRepoRoot 'scripts\amutorrent-interactive-session.py'
    if (-not (Test-Path -LiteralPath $sessionScriptPath -PathType Leaf)) {
        throw "Missing aMuTorrent interactive session runner: $sessionScriptPath"
    }

    $pythonInvocation = Get-PythonInvocation
    $arguments = @(
        $pythonInvocation.Prefix
        $sessionScriptPath
        '--workspace-root'
        $workspaceRoot
        '--app-root'
        $appRoot
        '--configuration'
        $entry.Configuration
    )
    if ($LiveNetwork) {
        $arguments += '--live-network'
    }

    Invoke-Native $pythonInvocation.FilePath $arguments 'aMuTorrent interactive session'
}

function Write-WorkspaceSummary {
    Write-Host ''
    Write-Host 'Workspace summary' -ForegroundColor Green
    foreach ($dependency in $Dependencies) {
        $repoPath = Resolve-WorkspacePath $dependency.Path
        if (-not (Test-Path -LiteralPath $repoPath)) {
            continue
        }
        Write-Host ("DEP {0,-12} {1} {2}" -f $dependency.Name, (Get-RepoBranch $repoPath), (Get-RepoHead $repoPath))
    }
    foreach ($app in Get-ActiveApps) {
        Write-Host ("APP {0,-12} {1} {2}" -f $app.Name, $app.CurrentBranch, (Get-RepoHead $app.Path))
    }
}

function Validate-Workspace {
    & $PSCommandPath env-check -EmuleWorkspaceRoot $EmuleWorkspaceRoot -WorkspaceName $WorkspaceName -Config $Config -Platform $Platform
    Assert-RequiredWorkspacePaths
    Assert-AppLayout
    Ensure-CanonicalAppAnchor

    $toolingRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tooling
    $policyAudits = @(
        @{ Name = 'build policy audit'; Path = (Join-Path $toolingRepoRoot 'ci\check-build-policy.ps1') }
        @{ Name = 'branch policy audit'; Path = (Join-Path $toolingRepoRoot 'ci\check-branch-policy.ps1') }
        @{ Name = 'dependency pin audit'; Path = (Join-Path $toolingRepoRoot 'ci\check-dependency-pins.ps1') }
        @{ Name = 'documentation path audit'; Path = (Join-Path $toolingRepoRoot 'ci\check-doc-paths.ps1') }
        @{ Name = 'editorconfig policy audit'; Path = (Join-Path $toolingRepoRoot 'ci\check-editorconfig-policy.ps1') }
        @{ Name = 'project entrypoint audit'; Path = (Join-Path $toolingRepoRoot 'ci\check-project-entrypoints.ps1') }
        @{ Name = 'warning policy audit'; Path = (Join-Path $toolingRepoRoot 'ci\check-warning-policy.ps1') }
    )
    foreach ($audit in $policyAudits) {
        if (-not (Test-Path -LiteralPath $audit.Path)) {
            throw "Missing required policy audit: $($audit.Path)"
        }
        Invoke-Native 'pwsh' @(
            '-NoLogo',
            '-NoProfile',
            '-ExecutionPolicy',
            'Bypass',
            '-File',
            $audit.Path,
            '-EmuleWorkspaceRoot',
            $EmuleWorkspaceRoot
        ) $audit.Name
    }

    $testRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tests
    foreach ($scriptPath in @(
        (Join-Path $testRepoRoot 'scripts\build-emule-tests.py'),
        (Join-Path $testRepoRoot 'scripts\run-native-coverage.py'),
        (Join-Path $testRepoRoot 'scripts\run-live-diff.py'),
        (Join-Path $testRepoRoot 'scripts\run-community-core-coverage.py'),
        (Join-Path $testRepoRoot 'scripts\run-live-e2e-suite.py'),
        (Join-Path $testRepoRoot 'scripts\amutorrent-interactive-session.py')
    )) {
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "Missing required test helper: $scriptPath"
        }
    }
}

# All top-level workspace commands are serialized behind one per-workspace lock.
# That lock is intentional: it prevents overlapping env-check/build/test flows
# from trampling the same state, logs, and outputs.
if (-not (Acquire-WorkspaceCommandLock)) {
    exit 1
}

if ($Command -in @('build-libs', 'build-app', 'build-tests', 'package-release', 'build-all', 'full')) {
    Reset-BuildExecutionState
}

try {
    switch ($Command) {
        'env-check' {
            $vs = Get-VsInfo
            if (-not $vs) { throw 'Visual Studio 2022 with MSBuild is required.' }
            if (-not (Resolve-Tool @('git.exe','git'))) { throw 'git not found on PATH.' }
            Write-Host "Visual Studio: $($vs.Root)"
            Write-Host "MSBuild: $($vs.MSBuild)"
            if (-not [string]::IsNullOrWhiteSpace($ToolsetOverrideVariable)) {
                Write-Host "Toolset override variable: $ToolsetOverrideVariable"
            }
        }
        'dep-status' {
            foreach ($dependency in $Dependencies) {
                $repoPath = Resolve-WorkspacePath $dependency.Path
                if (-not (Test-Path -LiteralPath $repoPath)) {
                    Write-Host ("MISSING {0} -> {1}" -f $dependency.Name, $repoPath)
                    continue
                }
                Write-Host ("DEP {0} [{1}] {2}" -f $dependency.Name, (Get-RepoBranch $repoPath), ((Get-RepoStatus $repoPath) -join '; '))
            }
            foreach ($app in Get-ActiveApps) {
                Write-Host ("APP {0} [{1}] {2}" -f $app.Path, $app.CurrentBranch, ((Get-RepoStatus $app.Path) -join '; '))
            }
        }
        'validate' {
            Validate-Workspace
        }
        'build-libs' {
            Build-Libs
        }
        'build-app' {
            Build-Apps
        }
        'build-tests' {
            Build-Tests
        }
        'python-tests' {
            Invoke-PythonTestRuns
        }
        'test' {
            Invoke-TestRuns
        }
        'live-diff' {
            Invoke-LiveDiffRuns -TestRunVariantName $(if ([string]::IsNullOrWhiteSpace($TestRunVariant)) { $TestTargets.TestRunVariant } else { $TestRunVariant }) -BaselineVariantName $(if ([string]::IsNullOrWhiteSpace($BaselineVariant)) { $TestTargets.BaselineVariant } else { $BaselineVariant })
        }
        'live-e2e' {
            Invoke-LiveE2eSuite
        }
        'amutorrent-session' {
            Invoke-AmutorrentInteractiveSession
        }
        'community-core-coverage' {
            Invoke-CommunityCoreCoverage -TestRunVariantName $(if ([string]::IsNullOrWhiteSpace($TestRunVariant)) { $TestTargets.TestRunVariant } else { $TestRunVariant }) -BaselineVariantName $(if ([string]::IsNullOrWhiteSpace($BaselineVariant)) { $TestTargets.BaselineVariant } else { $BaselineVariant })
        }
        'package-release' {
            New-ReleasePackage
        }
        'build-all' {
            Build-Libs
            Build-Apps
            Build-Tests
        }
        'full' {
            Build-Libs
            Build-Apps
            Build-Tests
            Invoke-TestRuns
            Write-WorkspaceSummary
        }
    }
} finally {
    if ($Command -in @('build-libs', 'build-app', 'build-tests', 'package-release', 'build-all', 'full')) {
        Write-BuildCommandRecap -CommandName $Command
    }
    Release-WorkspaceCommandLock
}

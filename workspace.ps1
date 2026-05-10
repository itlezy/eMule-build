#Requires -Version 7.6
<#
.SYNOPSIS
Compatibility shim for the Python eMule workspace orchestration CLI.

.DESCRIPTION
All build, validation, test, live-test, and packaging behavior lives in
`python -m emule_workspace`. This script only maps the former PowerShell
command shape onto the Python CLI.
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
    [int]$RestColdStartDumpStressDownloadsPerSearch = 1,
    [int]$RestColdStartDumpStressTargetCompletedDownloads = 0,
    [double]$RestColdStartDumpStressCompletionTimeoutSeconds = 1800.0,
    [int]$RestColdStartDumpStressMaxActiveDownloads = 128,
    [double]$RestColdStartDumpStressDownloadChurnIntervalSeconds = 0.0,
    [int]$RestColdStartDumpStressDownloadRemoveCountPerChurn = 0,
    [double]$RestColdStartDumpStressResourceMonitorIntervalSeconds = 5.0,
    [double]$RestColdStartDumpStressPostDrainSeconds = 30.0,
    [double]$RestColdStartDumpStressToolTimeoutSeconds = 600.0,
    [switch]$RestColdStartDumpStressEnableUmdh,
    [switch]$RestColdStartDumpStressSkipDumps,
    [ValidateSet('required', 'optional')]
    [string]$StartupTraceMode = 'required',
    [string]$SharedRoot,
    [string[]]$SharedFilesUiScenario,
    [int]$SharedFilesTreeStressChurnCycles = -1,
    [string]$ReleaseVersion = '1.1.1',
    [string]$P2PBindInterfaceName = 'hide.me',
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

function Add-Option([System.Collections.Generic.List[string]]$Arguments, [string]$Name, $Value) {
    if ($null -ne $Value -and -not [string]::IsNullOrWhiteSpace([string]$Value)) {
        $Arguments.Add($Name) | Out-Null
        $Arguments.Add([string]$Value) | Out-Null
    }
}

function Add-RepeatedOption([System.Collections.Generic.List[string]]$Arguments, [string]$Name, [string[]]$Values) {
    foreach ($value in @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        Add-Option $Arguments $Name $value
    }
}

function Add-Flag([System.Collections.Generic.List[string]]$Arguments, [string]$Name, [switch]$Value) {
    if ($Value) {
        $Arguments.Add($Name) | Out-Null
    }
}

function Add-CommonOptions([System.Collections.Generic.List[string]]$Arguments) {
    Add-Option $Arguments '--workspace-root' $EmuleWorkspaceRoot
    Add-Option $Arguments '--workspace-name' $WorkspaceName
    Add-Option $Arguments '--config' $Config
    Add-Option $Arguments '--platform' $Platform
    Add-Option $Arguments '--build-output-mode' $BuildOutputMode
}

function Add-LiveE2eOptions([System.Collections.Generic.List[string]]$Arguments) {
    Add-RepeatedOption $Arguments '--suite' $LiveSuite
    Add-Flag $Arguments '--fail-fast' $LiveFailFast
    Add-Flag $Arguments '--skip-live-seed-refresh' $SkipLiveSeedRefresh
    Add-Option $Arguments '--startup-trace-mode' $StartupTraceMode
    Add-Option $Arguments '--shared-root' $SharedRoot
    Add-RepeatedOption $Arguments '--shared-files-ui-scenario' $SharedFilesUiScenario
    Add-Option $Arguments '--shared-files-tree-stress-churn-cycles' $SharedFilesTreeStressChurnCycles
    Add-Option $Arguments '--p2p-bind-interface-name' $P2PBindInterfaceName
    Add-Option $Arguments '--rest-server-search-count' $RestServerSearchCount
    Add-Option $Arguments '--rest-kad-search-count' $RestKadSearchCount
    Add-Option $Arguments '--rest-download-trigger-count' $RestDownloadTriggerCount
    Add-Option $Arguments '--rest-search-method-override' $RestSearchMethodOverride
    Add-Option $Arguments '--rest-webserver-scheme' $RestWebServerScheme
    Add-Option $Arguments '--rest-coverage-budget' $RestCoverageBudget
    Add-Option $Arguments '--rest-stress-budget' $RestStressBudget
    Add-Option $Arguments '--rest-stress-duration-seconds' $RestStressDurationSeconds
    Add-Option $Arguments '--rest-stress-concurrency' $RestStressConcurrency
    Add-Option $Arguments '--rest-stress-max-failures' $RestStressMaxFailures
    Add-Option $Arguments '--rest-stress-request-timeout-seconds' $RestStressRequestTimeoutSeconds
    Add-Option $Arguments '--rest-socket-adversity-budget' $RestSocketAdversityBudget
    Add-Option $Arguments '--rest-tls-handshake-adversity-budget' $RestTlsHandshakeAdversityBudget
    Add-Option $Arguments '--rest-leak-churn-budget' $RestLeakChurnBudget
    Add-Option $Arguments '--rest-leak-churn-cycles' $RestLeakChurnCycles
    Add-Flag $Arguments '--rest-stop-start-after-churn' $RestStopStartAfterChurn
    Add-Option $Arguments '--rest-cold-start-dump-stress-waves' $RestColdStartDumpStressWaves
    Add-Option $Arguments '--rest-cold-start-dump-stress-searches-per-wave' $RestColdStartDumpStressSearchesPerWave
    Add-Option $Arguments '--rest-cold-start-dump-stress-max-concurrent-searches' $RestColdStartDumpStressMaxConcurrentSearches
    Add-Option $Arguments '--rest-cold-start-dump-stress-downloads-per-wave' $RestColdStartDumpStressDownloadsPerWave
    Add-Option $Arguments '--rest-cold-start-dump-stress-downloads-per-search' $RestColdStartDumpStressDownloadsPerSearch
    Add-Option $Arguments '--rest-cold-start-dump-stress-target-completed-downloads' $RestColdStartDumpStressTargetCompletedDownloads
    Add-Option $Arguments '--rest-cold-start-dump-stress-completion-timeout-seconds' $RestColdStartDumpStressCompletionTimeoutSeconds
    Add-Option $Arguments '--rest-cold-start-dump-stress-max-active-downloads' $RestColdStartDumpStressMaxActiveDownloads
    Add-Option $Arguments '--rest-cold-start-dump-stress-download-churn-interval-seconds' $RestColdStartDumpStressDownloadChurnIntervalSeconds
    Add-Option $Arguments '--rest-cold-start-dump-stress-download-remove-count-per-churn' $RestColdStartDumpStressDownloadRemoveCountPerChurn
    Add-Option $Arguments '--rest-cold-start-dump-stress-resource-monitor-interval-seconds' $RestColdStartDumpStressResourceMonitorIntervalSeconds
    Add-Option $Arguments '--rest-cold-start-dump-stress-post-drain-seconds' $RestColdStartDumpStressPostDrainSeconds
    Add-Option $Arguments '--rest-cold-start-dump-stress-tool-timeout-seconds' $RestColdStartDumpStressToolTimeoutSeconds
    Add-Flag $Arguments '--rest-cold-start-dump-stress-enable-umdh' $RestColdStartDumpStressEnableUmdh
    Add-Flag $Arguments '--rest-cold-start-dump-stress-skip-dumps' $RestColdStartDumpStressSkipDumps
}

if ($Help) {
    $Command = 'help'
}

$arguments = [System.Collections.Generic.List[string]]::new()
switch ($Command) {
    'help' {
        $arguments.Add('--help') | Out-Null
    }
    'env-check' {
        $arguments.Add('env-check') | Out-Null
        Add-CommonOptions $arguments
    }
    'dep-status' {
        $arguments.Add('dep-status') | Out-Null
        Add-CommonOptions $arguments
    }
    'validate' {
        $arguments.Add('validate') | Out-Null
        Add-CommonOptions $arguments
    }
    'build-libs' {
        $arguments.AddRange([string[]]@('build', 'libs'))
        Add-CommonOptions $arguments
        Add-Flag $arguments '--clean' $Clean
    }
    'build-app' {
        $arguments.AddRange([string[]]@('build', 'app'))
        Add-CommonOptions $arguments
        Add-Flag $arguments '--clean' $Clean
        Add-RepeatedOption $arguments '--variant' $AppVariant
    }
    'build-tests' {
        $arguments.AddRange([string[]]@('build', 'tests'))
        Add-CommonOptions $arguments
        Add-Flag $arguments '--clean' $Clean
        Add-Option $arguments '--test-run-variant' $TestRunVariant
    }
    'python-tests' {
        $arguments.AddRange([string[]]@('test', 'python'))
        Add-CommonOptions $arguments
        Add-Flag $arguments '--quiet' $PythonTestQuiet
        Add-RepeatedOption $arguments '--path' $PythonTestPath
        Add-Option $arguments '--expression' $PythonTestExpression
        foreach ($extra in @($PythonTestArgs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
            $arguments.Add($extra) | Out-Null
        }
    }
    'test' {
        $arguments.AddRange([string[]]@('test', 'all'))
        Add-CommonOptions $arguments
    }
    'live-diff' {
        $arguments.AddRange([string[]]@('test', 'live-diff'))
        Add-CommonOptions $arguments
        Add-Option $arguments '--test-run-variant' $TestRunVariant
        Add-Option $arguments '--baseline-variant' $BaselineVariant
    }
    'live-e2e' {
        $arguments.AddRange([string[]]@('test', 'live-e2e'))
        Add-CommonOptions $arguments
        Add-LiveE2eOptions $arguments
    }
    'amutorrent-session' {
        $arguments.AddRange([string[]]@('test', 'amutorrent-session'))
        Add-CommonOptions $arguments
        Add-Flag $arguments '--live-network' $LiveNetwork
    }
    'community-core-coverage' {
        $arguments.AddRange([string[]]@('test', 'community-core-coverage'))
        Add-CommonOptions $arguments
        Add-Option $arguments '--test-run-variant' $TestRunVariant
        Add-Option $arguments '--baseline-variant' $BaselineVariant
        Add-Option $arguments '--rest-coverage-budget' $RestCoverageBudget
        Add-Option $arguments '--rest-stress-budget' $RestStressBudget
    }
    'package-release' {
        $arguments.Add('package-release') | Out-Null
        Add-CommonOptions $arguments
        Add-Flag $arguments '--clean' $Clean
        Add-Option $arguments '--release-version' $ReleaseVersion
    }
    'build-all' {
        $arguments.AddRange([string[]]@('build', 'all'))
        Add-CommonOptions $arguments
        Add-Flag $arguments '--clean' $Clean
        Add-RepeatedOption $arguments '--variant' $AppVariant
        Add-Option $arguments '--test-run-variant' $TestRunVariant
    }
    'full' {
        $arguments.Add('full') | Out-Null
        Add-CommonOptions $arguments
        Add-Flag $arguments '--clean' $Clean
        Add-RepeatedOption $arguments '--variant' $AppVariant
        Add-Option $arguments '--test-run-variant' $TestRunVariant
    }
}

$python = Get-Command python -ErrorAction SilentlyContinue
$pythonPrefix = @()
if (-not $python) {
    $python = Get-Command py -ErrorAction SilentlyContinue
    $pythonPrefix = @('-3')
}
if (-not $python) {
    throw 'Python 3 was not found on PATH.'
}

$scriptRoot = Split-Path -Parent $PSCommandPath
Push-Location $scriptRoot
try {
    $pythonArguments = @($pythonPrefix + @('-m', 'emule_workspace') + $arguments)
    & $python.Source @pythonArguments
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
} finally {
    Pop-Location
}

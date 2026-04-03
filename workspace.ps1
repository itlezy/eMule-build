#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('env-check','dep-status','validate','setup','repair','build-libs','build-app','build-all','normalize','normalize-check')]
    [string]$Command,
    [ValidateSet('Release', 'Debug')]
    [string]$Config = 'Release',
    [ValidateSet('x64', 'ARM64')]
    [string]$Platform = 'x64'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$Root = Split-Path -Parent $PSCommandPath
$Manifest = Import-PowerShellDataFile -Path (Join-Path $Root 'deps.psd1')
$Workspace = $Manifest.Workspace
$Dependencies = @($Workspace.Dependencies)
$AppRepo = $Workspace.AppRepo
$Toolchain = $Workspace.Toolchain
$ToolsetOverrideVariable = $Toolchain.ToolsetOverrideVariable
$KnownAppBranches = @{}
foreach ($variant in $AppRepo.Variants) {
    $KnownAppBranches[$variant.Branch] = $variant.Name
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

function Invoke-Native([string]$FilePath, [string[]]$Arguments, [string]$Label, [string]$WorkingDirectory = $Root, [switch]$AllowFailure) {
    Push-Location $WorkingDirectory
    try {
        & $FilePath @Arguments
        $exitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "$Label failed with exit code $exitCode."
    }
    $exitCode
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

function Get-RepoStatus([string]$Repo) {
    @((Invoke-Git $Repo @('status','--short','--branch') 'git status') | Where-Object { $_ })
}

function Test-GitRef([string]$Repo, [string]$Ref) {
    $git = Resolve-Tool @('git.exe', 'git')
    if (-not $git) {
        return $false
    }
    & $git -C $Repo show-ref --verify --quiet $Ref 2>$null
    return $LASTEXITCODE -eq 0
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
        VcVars64 = Join-Path $installPath 'VC\Auxiliary\Build\vcvars64.bat'
    }
}

function Get-ActiveApps {
    $apps = [System.Collections.Generic.List[object]]::new()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $seedRepo = Join-Path $Root $AppRepo.SeedRepo
    if (Test-Path -LiteralPath $seedRepo) {
        $branch = Get-RepoBranch $seedRepo
        if ($KnownAppBranches.ContainsKey($branch)) {
            $null = $seen.Add([IO.Path]::GetFullPath($seedRepo))
            $apps.Add([pscustomobject]@{
                Name = $KnownAppBranches[$branch]
                Branch = $branch
                Path = $seedRepo
                Source = 'seed'
            }) | Out-Null
        }
    }

    foreach ($variant in $AppRepo.Variants) {
        $path = Resolve-Path -LiteralPath (Join-Path $Root $variant.Path) -ErrorAction SilentlyContinue
        if (-not $path) { continue }
        if ($seen.Contains($path.Path)) { continue }
        $branch = Get-RepoBranch $path.Path
        $apps.Add([pscustomobject]@{
            Name = $variant.Name
            Branch = $branch
            Path = $path.Path
            Source = 'worktree'
            ExpectedBranch = $variant.Branch
        }) | Out-Null
    }

    $apps
}

function Assert-AppLayout {
    foreach ($app in Get-ActiveApps) {
        if ($app.PSObject.Properties.Name -contains 'ExpectedBranch' -and $app.Branch -ne $app.ExpectedBranch) {
            throw "App checkout '$($app.Path)' is on branch '$($app.Branch)', expected '$($app.ExpectedBranch)'."
        }
    }
}

function Ensure-AppWorktrees {
    $seedRepo = Join-Path $Root $AppRepo.SeedRepo
    if (-not (Test-Path -LiteralPath $seedRepo)) {
        throw "Seed eMule repo missing at '$seedRepo'."
    }

    $currentSeedBranch = Get-RepoBranch $seedRepo
    foreach ($variant in $AppRepo.Variants) {
        $targetPath = Join-Path $Root $variant.Path
        if (Test-Path -LiteralPath $targetPath) {
            continue
        }
        if ($currentSeedBranch -eq $variant.Branch) {
            continue
        }

        $hasLocal = Test-GitRef $seedRepo "refs/heads/$($variant.Branch)"
        if (-not $hasLocal) {
            & git -C $seedRepo branch --track $variant.Branch "origin/$($variant.Branch)" | Out-Null
        }
        Invoke-Native 'git' @('-C', $seedRepo, 'worktree', 'add', $targetPath, $variant.Branch) "git worktree add $($variant.Branch)"
    }
}

function Ensure-PythonPackages {
    $python = Resolve-Tool @('python.exe', 'python')
    if (-not $python) {
        throw 'python not found on PATH.'
    }
    $requirements = Join-Path $Root 'requirements-normalizer.txt'
    Invoke-Native $python @('-m','pip','install','--disable-pip-version-check','--user','-r',$requirements) 'pip install'
}

function Get-NormalizeRoots {
    $roots = [System.Collections.Generic.List[string]]::new()
    $roots.Add($Root) | Out-Null

    foreach ($dependency in $Dependencies) {
        $path = Join-Path $Root $dependency.Repo
        if (Test-Path -LiteralPath $path) {
            $roots.Add((Resolve-Path -LiteralPath $path).Path) | Out-Null
        }
    }

    foreach ($app in Get-ActiveApps) {
        if (-not $roots.Contains($app.Path)) {
            $roots.Add($app.Path) | Out-Null
        }
    }

    $roots
}

function Invoke-BuildScript([string]$RelativeScript) {
    $scriptPath = Join-Path $Root $RelativeScript
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Build script '$RelativeScript' not found."
    }
    Invoke-Native 'cmd.exe' @('/d','/c', $scriptPath) $RelativeScript
}

function Build-Apps {
    Assert-AppLayout
    $msbuild = (Get-VsInfo).MSBuild
    if (-not $msbuild -or -not (Test-Path -LiteralPath $msbuild)) {
        throw 'MSBuild.exe was not found in the detected Visual Studio installation.'
    }

    $apps = @(Get-ActiveApps)
    if ($apps.Count -eq 0) {
        throw 'No supported eMule app checkout is present.'
    }

    foreach ($app in $apps) {
        $project = Join-Path $app.Path 'srchybrid\emule.vcxproj'
        if (-not (Test-Path -LiteralPath $project)) {
            throw "App project missing at '$project'."
        }
        Write-Host "==> Building eMule [$($app.Name)] $Config/$Platform" -ForegroundColor Cyan
        $workspaceRoot = [IO.Path]::GetFullPath($Root) + '\'
        $arguments = @(
            $project,
            '-target:Build',
            "/property:Configuration=$Config",
            "/property:Platform=$Platform",
            "/property:WorkspaceRoot=$workspaceRoot"
        )
        $override = [Environment]::GetEnvironmentVariable($ToolsetOverrideVariable)
        if ($override) {
            $arguments += "/property:PlatformToolset=$override"
        }
        Invoke-Native $msbuild $arguments "MSBuild eMule [$($app.Name)]" $app.Path
    }
}

switch ($Command) {
    'env-check' {
        $vs = Get-VsInfo
        if (-not $vs) { throw 'Visual Studio 2022 with MSBuild is required.' }
        if (-not (Resolve-Tool @('git.exe','git'))) { throw 'git not found on PATH.' }
        if (-not (Resolve-Tool @('python.exe','python'))) { throw 'python not found on PATH.' }
        Write-Host "Visual Studio: $($vs.Root)"
        Write-Host "MSBuild: $($vs.MSBuild)"
        Write-Host "Toolset override variable: $ToolsetOverrideVariable"
        if ([Environment]::GetEnvironmentVariable($ToolsetOverrideVariable)) {
            Write-Host "$ToolsetOverrideVariable=$([Environment]::GetEnvironmentVariable($ToolsetOverrideVariable))"
        }
    }
    'dep-status' {
        foreach ($dependency in $Dependencies) {
            $repo = Join-Path $Root $dependency.Repo
            if (-not (Test-Path -LiteralPath $repo)) {
                Write-Host ("MISSING {0} -> {1}" -f $dependency.Name, $dependency.Repo)
                continue
            }
            $branch = Get-RepoBranch $repo
            $status = (Get-RepoStatus $repo) -join '; '
            Write-Host ("DEP {0} [{1}] {2}" -f $dependency.Name, $branch, $status)
        }
        foreach ($app in Get-ActiveApps) {
            $status = (Get-RepoStatus $app.Path) -join '; '
            Write-Host ("APP {0} [{1}] {2}" -f $app.Path, $app.Branch, $status)
        }
    }
    'setup' {
        New-Item -ItemType Directory -Force -Path (Join-Path $Root 'libs') | Out-Null
        New-Item -ItemType Directory -Force -Path (Join-Path $Root 'libs_debug') | Out-Null
        Ensure-AppWorktrees
        Ensure-PythonPackages
        Assert-AppLayout
    }
    'repair' {
        Assert-AppLayout
        Ensure-PythonPackages
    }
    'validate' {
        & $PSCommandPath env-check -Config $Config -Platform $Platform
        & $PSCommandPath dep-status -Config $Config -Platform $Platform
        Assert-AppLayout
    }
    'build-libs' {
        foreach ($dependency in $Dependencies) {
            Write-Host "==> Building $($dependency.Name) $Config/$Platform" -ForegroundColor Cyan
            $script = $dependency.BuildScript[$Config]
            Invoke-BuildScript $script
        }
    }
    'build-app' {
        Build-Apps
    }
    'build-all' {
        & $PSCommandPath build-libs -Config $Config -Platform $Platform
        & $PSCommandPath build-app -Config $Config -Platform $Platform
    }
    'normalize' {
        Ensure-PythonPackages
        $python = Resolve-Tool @('python.exe', 'python')
        $scriptPath = Join-Path $Root 'scripts\source-normalizer.py'
        foreach ($normalizeRoot in Get-NormalizeRoots) {
            Write-Host "==> Normalizing $normalizeRoot" -ForegroundColor Cyan
            Invoke-Native $python @($scriptPath, '--root', $normalizeRoot, '--write', '--report-encodings') 'source-normalizer'
        }
    }
    'normalize-check' {
        Ensure-PythonPackages
        $python = Resolve-Tool @('python.exe', 'python')
        $scriptPath = Join-Path $Root 'scripts\source-normalizer.py'
        foreach ($normalizeRoot in Get-NormalizeRoots) {
            Write-Host "==> Checking normalization for $normalizeRoot" -ForegroundColor Cyan
            Invoke-Native $python @($scriptPath, '--root', $normalizeRoot, '--check', '--report-encodings') 'source-normalizer'
        }
    }
}

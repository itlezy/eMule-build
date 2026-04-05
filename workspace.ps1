#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('env-check','dep-status','validate','setup','repair','bootstrap','build-libs','build-app','build-all','normalize','normalize-check')]
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
$SeedRepo = $AppRepo.SeedRepo
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

function Test-RepoClean([string]$Repo) {
    $status = Invoke-Git $Repo @('status','--porcelain') 'git status'
    return @($status | Where-Object { $_ }).Count -eq 0
}

function Get-RepoHead([string]$Repo) {
    ((Invoke-Git $Repo @('rev-parse','--short','HEAD') 'git rev-parse') -join "`n").Trim()
}

function Get-RepoHeadFull([string]$Repo) {
    ((Invoke-Git $Repo @('rev-parse','HEAD') 'git rev-parse') -join "`n").Trim()
}

function Test-GitRef([string]$Repo, [string]$Ref) {
    $git = Resolve-Tool @('git.exe', 'git')
    if (-not $git) {
        return $false
    }
    & $git -C $Repo show-ref --verify --quiet $Ref 2>$null
    return $LASTEXITCODE -eq 0
}

function Ensure-RemoteTrackingBranch([string]$Repo, [string]$Branch) {
    if (Test-GitRef $Repo "refs/remotes/origin/$Branch") {
        return
    }

    Invoke-Native 'git' @(
        '-C', $Repo,
        'fetch', 'origin',
        "refs/heads/${Branch}:refs/remotes/origin/${Branch}"
    ) "git fetch origin/$Branch"
}

function Ensure-LocalBranch([string]$Repo, [string]$Branch) {
    if (Test-GitRef $Repo "refs/heads/$Branch") {
        return
    }

    Ensure-RemoteTrackingBranch $Repo $Branch
    Invoke-Native 'git' @(
        '-C', $Repo,
        'branch', $Branch,
        "refs/remotes/origin/$Branch"
    ) "git branch $Branch"
}

function Test-GitCommit([string]$Repo, [string]$Commit) {
    $git = Resolve-Tool @('git.exe', 'git')
    if (-not $git) {
        return $false
    }

    & $git -C $Repo rev-parse --verify --quiet "$Commit^{commit}" 2>$null | Out-Null
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

    $seedRepo = Join-Path $Root $SeedRepo.Path
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
    $seedRepo = Join-Path $Root $SeedRepo.Path
    if (-not (Test-Path -LiteralPath $seedRepo)) {
        throw "Seed eMule repo missing at '$seedRepo'."
    }

    $currentSeedBranch = Get-RepoBranch $seedRepo
    foreach ($variant in $AppRepo.Variants) {
        $targetPath = Join-Path $Root $variant.Path
        if (-not (Test-Path -LiteralPath $targetPath)) {
            if ($currentSeedBranch -eq $variant.Branch) {
                continue
            }

            Ensure-LocalBranch $seedRepo $variant.Branch
            Invoke-Native 'git' @('-C', $seedRepo, 'worktree', 'add', $targetPath, $variant.Branch) "git worktree add $($variant.Branch)"
        }

        Sync-RepoBranchHead -Path $targetPath -Branch $variant.Branch -Label "app variant '$($variant.Name)'"
    }
}

function Ensure-Repo([string]$Path, [string]$Url, [string]$Branch, [string]$Label, [string]$Commit = $null) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Host "==> Cloning $Label into $Path" -ForegroundColor Cyan
        if ($Commit) {
            Invoke-Native 'git' @('clone', $Url, $Path) "git clone $Label"
        } elseif ($Branch) {
            Invoke-Native 'git' @('clone', '--branch', $Branch, '--single-branch', $Url, $Path) "git clone $Label"
        } else {
            Invoke-Native 'git' @('clone', $Url, $Path) "git clone $Label"
        }
    }

    if (-not (Test-Path -LiteralPath (Join-Path $Path '.git'))) {
        throw "$Label path '$Path' exists but is not a git repository."
    }

    Write-Host "==> Refreshing $Label" -ForegroundColor Cyan
    Invoke-Native 'git' @('-C', $Path, 'fetch', '--all', '--prune') "git fetch $Label"

    if ($Commit) {
        if (-not (Test-GitCommit $Path $Commit)) {
            Invoke-Native 'git' @('-C', $Path, 'fetch', 'origin', $Commit) "git fetch $Label commit"
        }

        $currentCommit = Get-RepoHeadFull $Path
        if ($currentCommit -eq $Commit) {
            return
        }

        if (-not (Test-RepoClean $Path)) {
            throw "$Label at '$Path' is not at pinned commit '$Commit', and the repo is dirty."
        }

        Invoke-Native 'git' @('-C', $Path, 'checkout', '--detach', $Commit) "git checkout $Label"
        return
    }

    if (-not $Branch) {
        return
    }

    $currentBranch = Get-RepoBranch $Path
    if ($currentBranch -eq $Branch) {
        return
    }

    if (-not (Test-RepoClean $Path)) {
        throw "$Label at '$Path' is on branch '$currentBranch' but should be '$Branch', and the repo is dirty."
    }

    if (-not (Test-GitRef $Path "refs/heads/$Branch")) {
        Ensure-LocalBranch $Path $Branch
    }

    Invoke-Native 'git' @('-C', $Path, 'switch', $Branch) "git switch $Label"
}

function Sync-RepoBranchHead([string]$Path, [string]$Branch, [string]$Label) {
    Ensure-RemoteTrackingBranch $Path $Branch

    $currentBranch = Get-RepoBranch $Path
    if ($currentBranch -ne $Branch) {
        if (-not (Test-RepoClean $Path)) {
            throw "$Label at '$Path' is on branch '$currentBranch' but should be '$Branch', and the repo is dirty."
        }

        Ensure-LocalBranch $Path $Branch
        Invoke-Native 'git' @('-C', $Path, 'switch', $Branch) "git switch $Label"
    }

    if (-not (Test-RepoClean $Path)) {
        throw "$Label at '$Path' is dirty and cannot be fast-forwarded to origin/$Branch."
    }

    Invoke-Native 'git' @('-C', $Path, 'merge', '--ff-only', "refs/remotes/origin/$Branch") "git merge --ff-only $Label"
}

function Ensure-DependencyRepos {
    foreach ($dependency in $Dependencies) {
        $repo = Join-Path $Root $dependency.Repo
        Ensure-Repo -Path $repo -Url $dependency.Url -Branch $dependency.Branch -Commit $dependency.Commit -Label "dependency '$($dependency.Name)'"
    }
}

function Ensure-AppSeedRepo {
    $repo = Join-Path $Root $SeedRepo.Path
    Ensure-Repo -Path $repo -Url $SeedRepo.Url -Branch $SeedRepo.Branch -Label 'seed app repo'
    Sync-RepoBranchHead -Path $repo -Branch $SeedRepo.Branch -Label 'seed app repo'
}

function Repair-AppWorktreeMetadata {
    $seedRepo = Join-Path $Root $SeedRepo.Path
    if (-not (Test-Path -LiteralPath $seedRepo)) {
        return
    }

    $paths = [System.Collections.Generic.List[string]]::new()
    $paths.Add([IO.Path]::GetFullPath($seedRepo)) | Out-Null
    foreach ($variant in $AppRepo.Variants) {
        $targetPath = Join-Path $Root $variant.Path
        if (Test-Path -LiteralPath $targetPath) {
            $paths.Add([IO.Path]::GetFullPath($targetPath)) | Out-Null
        }
    }

    if ($paths.Count -gt 0) {
        Invoke-Native 'git' (@('-C', $seedRepo, 'worktree', 'repair') + $paths.ToArray()) 'git worktree repair' -AllowFailure
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

function Write-WorkspaceSummary {
    Write-Host ''
    Write-Host 'Workspace summary' -ForegroundColor Green
    foreach ($dependency in $Dependencies) {
        $repo = Join-Path $Root $dependency.Repo
        if (-not (Test-Path -LiteralPath $repo)) { continue }
        Write-Host ("DEP {0,-12} {1} {2}" -f $dependency.Name, (Get-RepoBranch $repo), (Get-RepoHead $repo))
    }
    foreach ($app in Get-ActiveApps) {
        Write-Host ("APP {0,-12} {1} {2}" -f $app.Name, $app.Branch, (Get-RepoHead $app.Path))
    }
    Write-Host ("Outputs       libs={0} libs_debug={1}" -f (Join-Path $Root 'libs'), (Join-Path $Root 'libs_debug'))
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
        Ensure-DependencyRepos
        Ensure-AppSeedRepo
        Repair-AppWorktreeMetadata
        Ensure-AppWorktrees
        Ensure-PythonPackages
        Assert-AppLayout
    }
    'repair' {
        Ensure-DependencyRepos
        Ensure-AppSeedRepo
        Repair-AppWorktreeMetadata
        Ensure-AppWorktrees
        Assert-AppLayout
        Ensure-PythonPackages
    }
    'bootstrap' {
        & $PSCommandPath env-check -Config $Config -Platform $Platform
        & $PSCommandPath setup -Config $Config -Platform $Platform
        & $PSCommandPath build-libs -Config $Config -Platform $Platform
        & $PSCommandPath build-app -Config $Config -Platform $Platform
        Write-WorkspaceSummary
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

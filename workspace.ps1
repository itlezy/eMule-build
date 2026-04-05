#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('env-check','dep-status','validate','validate-full','setup','repair','bootstrap','build-libs','build-app','build-all','package','normalize','normalize-check')]
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
$GeneratedProjects = if ($Workspace.ContainsKey('GeneratedProjects')) { $Workspace.GeneratedProjects } else { @{} }
$Toolchain = $Workspace.Toolchain
$ToolsetOverrideVariable = $Toolchain.ToolsetOverrideVariable
$DependencyOrder = if ($Manifest.ContainsKey('DependencyOrder')) { @($Manifest.DependencyOrder) } else { @($Dependencies | ForEach-Object { $_.Name }) }
$BuildProjects = if ($Manifest.ContainsKey('BuildProjects')) { @($Manifest.BuildProjects) } else { @($DependencyOrder) }
$Projects = if ($Manifest.ContainsKey('Projects')) { $Manifest.Projects } else { @{} }
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

function Get-WorkspaceReport {
    $results = [System.Collections.Generic.List[object]]::new()

    $requiredPaths = [System.Collections.Generic.List[string]]::new()
    $requiredPaths.Add('libs') | Out-Null
    $requiredPaths.Add('libs_debug') | Out-Null
    foreach ($variant in @($AppRepo.Variants)) {
        $requiredPaths.Add([string]$variant.Path) | Out-Null
    }

    $missing = @($requiredPaths | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Root $_)) })
    Add-Check $results $(if ($missing.Count -eq 0) { 'pass' } else { 'fail' }) 'workspace' $(if ($missing.Count -eq 0) { 'required paths present' } else { 'missing: ' + ($missing -join ', ') })

    foreach ($dependency in $Dependencies) {
        $repoPath = Join-Path $Root $dependency.Repo
        $status = if (-not (Test-Path -LiteralPath $repoPath)) {
            'fail'
        } elseif ($dependency.Commit) {
            $(if ((Get-RepoHeadFull $repoPath) -eq $dependency.Commit -and (Test-RepoClean $repoPath)) { 'pass' } else { 'fail' })
        } else {
            $branchOk = (Get-RepoBranch $repoPath) -eq $dependency.Branch
            $(if ($branchOk -and (Test-RepoClean $repoPath)) { 'pass' } else { 'fail' })
        }

        if ($status -eq 'pass') {
            $detail = if ($dependency.Commit) {
                "{0}; pinned {1}; clean" -f (Get-RepoHead $repoPath), $dependency.Commit
            } else {
                "{0}; clean" -f (Get-RepoBranch $repoPath)
            }
        } else {
            $detail = if (-not (Test-Path -LiteralPath $repoPath)) {
                'repo missing'
            } elseif ($dependency.Commit) {
                "{0}; expected pinned {1}; {2}" -f (Get-RepoHeadFull $repoPath), $dependency.Commit, $(if (Test-RepoClean $repoPath) { 'clean' } else { 'dirty' })
            } else {
                "{0}; expected {1}; {2}" -f (Get-RepoBranch $repoPath), $dependency.Branch, $(if (Test-RepoClean $repoPath) { 'clean' } else { 'dirty' })
            }
        }

        Add-Check $results $status "$($dependency.Name)-branch" $detail
    }

    foreach ($name in @($GeneratedProjects.Keys)) {
        $ready = Test-GeneratedProjectReady $name
        $profile = Get-GeneratedProjectProfile $name
        Add-Check $results $(if ($ready) { 'pass' } else { 'fail' }) "$name-configure" $(if ($ready) { ($profile.ConfigureReady -join ', ') } else { 'missing or incomplete; run setup/repair' })
    }

    @($results)
}

function Get-PackageArchiveCheck([string]$Configuration, [switch]$Optional) {
    $zip = Get-PackagePath $Configuration
    if (-not (Test-Path -LiteralPath $zip)) {
        return [pscustomobject]@{
            Status = $(if ($Optional) { 'warn' } else { 'fail' })
            Name = 'package-archive'
            Detail = "missing: $zip"
        }
    }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
        $entries = @($archive.Entries | Select-Object -ExpandProperty FullName)
        $missingEntries = @(Get-PackageEntryList $Configuration | Where-Object { $_ -notin $entries })
        if ($missingEntries.Count -gt 0) {
            return [pscustomobject]@{
                Status = 'fail'
                Name = 'package-archive'
                Detail = "missing entries $($missingEntries -join ', ') in $zip"
            }
        }

        return [pscustomobject]@{
            Status = 'pass'
            Name = 'package-archive'
            Detail = "$zip => $($entries -join ', ')"
        }
    } finally {
        if ($archive) {
            $archive.Dispose()
        }
    }
}

function Get-BuildStateReport([string]$Configuration, [switch]$SkipPackageArchive) {
    $results = [System.Collections.Generic.List[object]]::new()

    foreach ($name in $BuildProjects) {
        $out = Get-OutputPath $name $Configuration
        Add-Check $results $(if (Test-Path -LiteralPath $out) { 'pass' } else { 'fail' }) "$name-output" $(if (Test-Path -LiteralPath $out) { $out } else { "missing: $out" })
    }

    $exe = Get-OutputPath 'eMule' $Configuration
    Add-Check $results $(if (Test-Path -LiteralPath $exe) { 'pass' } else { 'fail' }) 'emule-output' $(if (Test-Path -LiteralPath $exe) { $exe } else { "missing: $exe" })

    if ($Configuration -eq 'Release' -and $Workspace.ContainsKey('Package') -and -not $SkipPackageArchive) {
        Add-Checks $results (Get-PackageArchiveCheck $Configuration)
    }

    @($results)
}

function Get-EnvReport([switch]$Full, [switch]$SkipPackageArchive) {
    $results = [System.Collections.Generic.List[object]]::new()
    $tools = Get-ToolsContext

    Add-Check $results $(if ($tools.Vs) { 'pass' } else { 'fail' }) 'visual-studio' $(if ($tools.Vs) { $tools.Vs.Root } else { 'Visual Studio 2022 with MSBuild is required.' })
    Add-Check $results $(if ($tools.Git) { 'pass' } else { 'fail' }) 'git' $(if ($tools.Git) { $tools.Git } else { 'git not found on PATH.' })
    Add-Check $results $(if ($tools.Python) { 'pass' } else { 'fail' }) 'python' $(if ($tools.Python) { $tools.Python } else { 'python not found on PATH.' })

    Add-Checks $results (Get-WorkspaceReport)
    if ($Full) {
        Add-Checks $results (Get-BuildStateReport -Configuration $Config -SkipPackageArchive:$SkipPackageArchive)
    }

    [pscustomobject]@{
        Results = @($results)
        Failed = (@($results | Where-Object Status -eq 'fail')).Count
        Tools = $tools
    }
}

function Show-Report($Report) {
    foreach ($item in $Report.Results) {
        $color = @{ pass='Green'; warn='Yellow'; fail='Red' }[$item.Status]
        Write-Host ("[{0}] {1}: {2}" -f $item.Status.ToUpper(), $item.Name, $item.Detail) -ForegroundColor $color
    }

    if ($Report.Failed -gt 0) {
        throw 'Environment check failed.'
    }
}

function Get-PackageStageDir([string]$Configuration = 'Release') {
    Join-Path $Root ('dist\stage-{0}' -f $Configuration.ToLowerInvariant())
}

function New-PackageBuildInfo([string]$Configuration = 'Release') {
    $toolsContext = Get-ToolsContext
    @(
        "PackageRoot: $(Get-PackageRootDir $Configuration)"
        "SourceProject: $((Get-PackageProfile $Configuration).SourceProject)"
        "Configuration: $Configuration"
        "BuiltUtc: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
        "WorkspaceBranch: $(Get-RepoBranch $Root)"
        "WorkspaceCommit: $(Get-RepoHeadFull $Root)"
        "eMuleCommit: $(Get-RepoHead (Join-Path $Root $SeedRepo.Path))"
        "Binary: $(Split-Path -Leaf (Get-OutputPath 'eMule' $Configuration))"
        "PowerShell: $($PSVersionTable.PSVersion)"
        "MSBuild: $($toolsContext.Vs.MSBuild)"
        "VisualStudio: $($toolsContext.Vs.Root)"
    ) -join [Environment]::NewLine
}

function New-PackageStage([string]$Configuration = 'Release') {
    $profile = Get-PackageProfile $Configuration
    $stageDir = Get-PackageStageDir $Configuration
    if (Test-Path -LiteralPath $stageDir) {
        Remove-Item -LiteralPath $stageDir -Recurse -Force
    }

    $packageRoot = Join-Path $stageDir $profile.RootDir
    $null = New-Item -ItemType Directory -Path $packageRoot -Force
    Copy-Item -LiteralPath (Get-OutputPath $profile.SourceProject $Configuration) -Destination (Join-Path $packageRoot $profile.Entry) -Force

    foreach ($item in @($profile.Include)) {
        $destination = Join-Path $packageRoot $item.Destination
        $parent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $parent)) {
            $null = New-Item -ItemType Directory -Path $parent -Force
        }
        Copy-Item -LiteralPath (Get-WorkspacePath $item.Source) -Destination $destination -Force
    }

    if ($profile.BuildInfoName) {
        [IO.File]::WriteAllText((Join-Path $packageRoot $profile.BuildInfoName), (New-PackageBuildInfo $Configuration))
    }

    $stageDir
}

function New-PackageZip([string]$SourceFile, [string]$DestinationZip) {
    $destinationDir = Split-Path -Parent $DestinationZip
    if (-not (Test-Path -LiteralPath $destinationDir)) {
        $null = New-Item -ItemType Directory -Path $destinationDir -Force
    }
    if (Test-Path -LiteralPath $DestinationZip) {
        Remove-Item -LiteralPath $DestinationZip -Force
    }

    $sourceDir = Split-Path -Parent $SourceFile
    $leaf = Split-Path -Leaf $SourceFile
    Push-Location $sourceDir
    try {
        Compress-Archive -LiteralPath ".\$leaf" -DestinationPath $DestinationZip -CompressionLevel Optimal
    } finally {
        Pop-Location
    }
}

function Add-Check($List, [string]$Status, [string]$Name, [string]$Detail) {
    $List.Add([pscustomobject]@{ Status = $Status; Name = $Name; Detail = $Detail }) | Out-Null
}

function Add-Checks($List, $Checks) {
    foreach ($check in @($Checks)) {
        if ($check) {
            $List.Add($check) | Out-Null
        }
    }
}

function Get-WorkspacePath([string]$RelativePath) {
    Join-Path $Root $RelativePath
}

function Get-OutputPath([string]$Name, [string]$Configuration) {
    Join-Path $Root $Projects[$Name].Output[$Configuration]
}

function Test-GeneratedProjectDefined([string]$Name) {
    $null -ne $GeneratedProjects[$Name]
}

function Get-GeneratedProjectProfile([string]$Name) {
    $profile = $GeneratedProjects[$Name]
    if (-not $profile) {
        throw "No generated project profile defined for $Name."
    }
    $profile
}

function Test-GeneratedProjectReady([string]$Name) {
    if (-not (Test-GeneratedProjectDefined $Name)) {
        return $false
    }

    foreach ($relativePath in @((Get-GeneratedProjectProfile $Name).ConfigureReady)) {
        if (-not (Test-Path -LiteralPath (Get-WorkspacePath $relativePath))) {
            return $false
        }
    }

    return $true
}

function Get-PackageProfile([string]$Configuration = 'Release') {
    if (-not $Workspace.ContainsKey('Package')) {
        throw 'No package profiles are defined.'
    }

    $profile = $Workspace.Package[$Configuration]
    if (-not $profile) {
        throw "No package profile defined for configuration $Configuration."
    }

    $profile
}

function Get-PackageOutputDir([string]$Configuration = 'Release') {
    $profile = Get-PackageProfile $Configuration
    if ([string]::IsNullOrWhiteSpace($profile.OutputDir)) {
        return $Root
    }

    Join-Path $Root $profile.OutputDir
}

function Get-PackagePath([string]$Configuration = 'Release') {
    $profile = Get-PackageProfile $Configuration
    $archiveName = if ($profile.ContainsKey('ArchiveName')) { $profile.ArchiveName } else { $profile.Archive }
    if ([string]::IsNullOrWhiteSpace($archiveName)) {
        throw "No package archive name defined for configuration $Configuration."
    }

    Join-Path (Get-PackageOutputDir $Configuration) $archiveName
}

function Get-PackageRootDir([string]$Configuration = 'Release') {
    $profile = Get-PackageProfile $Configuration
    if ([string]::IsNullOrWhiteSpace($profile.RootDir)) {
        throw "No package root directory defined for configuration $Configuration."
    }

    $profile.RootDir
}

function Get-PackageEntryPath([string]$Configuration = 'Release', [string]$Entry) {
    '{0}/{1}' -f (Get-PackageRootDir $Configuration), (($Entry -replace '\\','/').TrimStart('/'))
}

function Get-PackageEntryList([string]$Configuration = 'Release') {
    $profile = Get-PackageProfile $Configuration
    $entries = [System.Collections.Generic.List[string]]::new()
    $entries.Add((Get-PackageEntryPath $Configuration $profile.Entry)) | Out-Null
    if ($profile.BuildInfoName) {
        $entries.Add((Get-PackageEntryPath $Configuration $profile.BuildInfoName)) | Out-Null
    }
    foreach ($item in @($profile.Include)) {
        if ($item.Destination) {
            $entries.Add((Get-PackageEntryPath $Configuration $item.Destination)) | Out-Null
        }
    }

    @($entries)
}

function Get-ToolsContext {
    $git = Resolve-Tool @('git.exe', 'git')
    $python = Resolve-Tool @('python.exe', 'python')
    $vs = Get-VsInfo
    [pscustomobject]@{
        Git = $git
        Python = $python
        Vs = $vs
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
        $report = Get-EnvReport
        Show-Report $report
        & $PSCommandPath dep-status -Config $Config -Platform $Platform
        Assert-AppLayout
    }
    'validate-full' {
        $report = Get-EnvReport -Full
        Show-Report $report
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
    'package' {
        if ($Config -ne 'Release') {
            throw 'Packaging is only supported for Release.'
        }
        $report = Get-EnvReport -Full -SkipPackageArchive
        Show-Report $report
        $zip = Get-PackagePath 'Release'
        $stageDir = New-PackageStage 'Release'
        New-PackageZip -SourceFile (Join-Path $stageDir (Get-PackageRootDir 'Release')) -DestinationZip $zip
        Write-Host "Package created at $zip" -ForegroundColor Green
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

#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('env-check','dep-status','validate','setup','repair','build-libs','build-app','build-all','build-project','open-solution','open-project','run-binary','package','clean-config','clean-generated')]
    [string]$Command,
    [ValidateSet('Release', 'Debug')]
    [string]$Config = 'Release',
    [ValidateSet('cryptopp', 'id3lib', 'miniupnp', 'ResizableLib', 'zlib', 'mbedtls', 'eMule')]
    [string]$Project = 'eMule',
    [ValidateSet('default', 'local', 'both')]
    [string]$Dirs = 'default',
    [switch]$NoBuildClean
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$Root = Split-Path -Parent $PSCommandPath
$Manifest = Import-PowerShellDataFile -Path (Join-Path $Root 'deps.psd1')
$Workspace = $Manifest.Workspace
$GeneratedProjects = $Workspace.GeneratedProjects
$Toolchain = $Workspace.Toolchain
$BuildBranch = $Manifest.BuildBranch
$AppBuildBranch = $Manifest.AppBuildBranch
$DependencyPatches = $Manifest.Dependencies
$NestedSubmodules = @($Manifest.NestedSubmodules)
$DependencyOrder = @($Manifest.DependencyOrder)
$BuildProjects = @($Manifest.BuildProjects)
$Projects = $Manifest.Projects
$LogsRoot = Join-Path $Root $Workspace.LogsRoot
$RunLogLabel = switch ($Command) {
    'build-project' { "$Command-$Project-$Config" }
    { $_ -in @('build-libs','build-app','build-all','setup','repair','package','run-binary','clean-config','validate') } { "$Command-$Config" }
    default { $Command }
}
$RunLogs = Join-Path $LogsRoot ("{0}-{1}" -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $RunLogLabel)

function Resolve-Tool([string[]]$Names) {
    foreach ($name in $Names) {
        $cmd = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($cmd) { return $cmd.Source }
    }
    $null
}

function Resolve-FirstExisting([string[]]$Paths) {
    foreach ($path in $Paths) {
        if ($path -and (Test-Path -LiteralPath $path)) {
            return (Resolve-Path -LiteralPath $path).Path
        }
    }
    $null
}

function Get-WorkspacePath([string]$RelativePath) {
    Join-Path $Root $RelativePath
}

function Get-PatchPath([string]$PatchFile) {
    Join-Path $Root "patches\$PatchFile"
}

function Get-GitExe {
    Resolve-Tool @('git.exe', 'git')
}

function Get-PerlExe {
    $perl = Resolve-Tool @('perl.exe', 'perl')
    if ($perl) { return $perl }

    $git = Get-GitExe
    if ($git) {
        $gitRoot = Split-Path -Parent (Split-Path -Parent $git)
        $bundled = Join-Path $gitRoot 'usr\bin\perl.exe'
        if (Test-Path -LiteralPath $bundled) { return $bundled }
    }

    foreach ($candidate in @(
        'C:\Program Files\Git\usr\bin\perl.exe',
        'C:\Strawberry\perl\bin\perl.exe'
    )) {
        if (Test-Path -LiteralPath $candidate) { return $candidate }
    }

    $null
}

function Invoke-Git([string]$Repo, [string[]]$ArgumentList, [string]$Label, [switch]$AllowFailure) {
    $git = Get-GitExe
    if (-not $git) { throw 'git not found on PATH.' }
    $stderrPath = Join-Path ([IO.Path]::GetTempPath()) ("workspace-git-stderr-{0}.log" -f ([guid]::NewGuid().ToString('N')))
    try {
        $output = & $git -C $Repo @ArgumentList 2> $stderrPath
        $exitCode = $LASTEXITCODE
        if ($exitCode -ne 0 -and -not $AllowFailure) {
            $stderr = if (Test-Path -LiteralPath $stderrPath) {
                (Get-Content -LiteralPath $stderrPath -Raw).Trim()
            } else {
                ''
            }
            if ([string]::IsNullOrWhiteSpace($stderr)) {
                throw "$Label failed with exit code $exitCode."
            }
            throw "$Label failed with exit code $exitCode.`n$stderr"
        }
    } finally {
        if (Test-Path -LiteralPath $stderrPath) {
            Remove-Item -LiteralPath $stderrPath -Force -ErrorAction SilentlyContinue
        }
    }
    @($output)
}

function Get-GitText([string]$Repo, [string[]]$ArgumentList, [string]$Label, [switch]$AllowFailure) {
    (($null + (Invoke-Git $Repo $ArgumentList $Label -AllowFailure:$AllowFailure)) -join "`n").Trim()
}

function Test-GitRef([string]$Repo, [string]$Ref) {
    $git = Get-GitExe
    if (-not $git) { return $false }
    & $git -C $Repo show-ref --verify --quiet $Ref 2>$null
    $LASTEXITCODE -eq 0
}

function Get-RepoStatus([string]$Repo) {
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $repoPath = [IO.Path]::GetFullPath($Repo).TrimEnd('\','/')
    $ignoredPrefixes = [System.Collections.Generic.List[string]]::new()

    foreach ($name in @($GeneratedProjects.Keys)) {
        $profile = $GeneratedProjects[$name]
        foreach ($relativePath in @($profile.Cleanup)) {
            $fullPath = [IO.Path]::GetFullPath((Join-Path $Root $relativePath)).TrimEnd('\','/')
            if ($fullPath.StartsWith($repoPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $relativeToRepo = $fullPath.Substring($repoPath.Length).TrimStart('\','/')
                if (-not [string]::IsNullOrWhiteSpace($relativeToRepo)) {
                    $ignoredPrefixes.Add(($relativeToRepo -replace '\\','/')) | Out-Null
                }
            }
        }
    }

    @((Invoke-Git $Repo @('status','--porcelain=v1','--untracked-files=all') 'git status') |
        Where-Object { $_ } |
        Where-Object {
            $entry = $_
            if ($entry.Length -lt 4) { return $true }
            $path = $entry.Substring(3).Trim() -replace '\\','/'
            foreach ($prefix in $ignoredPrefixes) {
                if ($path -eq $prefix -or $path.StartsWith("$prefix/")) {
                    return $false
                }
            }
            return $true
        })
}

function Get-RepoBranch([string]$Repo) {
    Get-GitText $Repo @('rev-parse','--abbrev-ref','HEAD') 'git rev-parse'
}

function Get-RepoHeadShort([string]$Repo) {
    Get-GitText $Repo @('rev-parse','--short','HEAD') 'git rev-parse --short'
}

function Get-GitIdentity([string]$Repo) {
    [pscustomobject]@{
        Name = Get-GitText $Repo @('config','--get','user.name') 'git config user.name' -AllowFailure
        Email = Get-GitText $Repo @('config','--get','user.email') 'git config user.email' -AllowFailure
    }
}

function Get-PatchPaths([string]$PatchFile) {
    $path = Get-PatchPath $PatchFile
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($line in [IO.File]::ReadLines($path)) {
        if ($line -match '^diff --git a/(.+?) b/(.+)$') {
            $paths.Add($Matches[2]) | Out-Null
        }
    }
    @($paths | Select-Object -Unique)
}

function Test-PatchApplied([string]$Repo, [string]$PatchFile) {
    $git = Get-GitExe
    if (-not $git) { return $false }
    & $git -C $Repo apply --reverse --check --ignore-whitespace (Get-PatchPath $PatchFile) 2>$null
    $LASTEXITCODE -eq 0
}

function Test-PatchCanApply([string]$Repo, [string]$PatchFile) {
    $git = Get-GitExe
    if (-not $git) { return $false }
    & $git -C $Repo apply --check --ignore-whitespace (Get-PatchPath $PatchFile) 2>$null
    $LASTEXITCODE -eq 0
}

function Get-StagedPaths([string]$Repo) {
    @((Invoke-Git $Repo @('diff','--cached','--name-only') 'git diff --cached') | Where-Object { $_ })
}

function Ensure-BuildBranch([string]$RepoRelative, [string]$Label, [string]$BranchName = $BuildBranch) {
    $repo = Join-Path $Root $RepoRelative
    $currentBranch = Get-RepoBranch $repo
    if ($currentBranch -eq $BranchName) { return }

    $branchExists = Test-GitRef $repo "refs/heads/$BranchName"

    if ($branchExists) {
        Invoke-Git $repo @('switch', $BranchName) "git switch $BranchName" | Out-Null
        return
    }

    Invoke-Git $repo @('switch', '-c', $BranchName) "git switch -c $BranchName" | Out-Null
}

function Ensure-PatchCommit([string]$DependencyKey) {
    $meta = $DependencyPatches[$DependencyKey]
    $repo = Join-Path $Root $meta.Repo
    $patch = if ($meta.Contains('Patch')) { $meta.Patch } else { $null }

    Ensure-BuildBranch $meta.Repo $DependencyKey

    if (-not $patch) {
        Write-Host "  $DependencyKey has no patch to apply (baked into branch)" -ForegroundColor DarkGray
        return
    }

    $patchAppliedBefore = Test-PatchApplied $repo $patch

    if (-not (Test-PatchApplied $repo $patch)) {
        if (-not (Test-PatchCanApply $repo $patch)) {
            throw "$DependencyKey patch $patch cannot be applied cleanly."
        }
        Write-Host "  Applying $patch" -ForegroundColor Cyan
        Invoke-Git $repo @('apply','--3way','--ignore-whitespace',(Get-PatchPath $patch)) "git apply $patch" | Out-Null
    } elseif (-not $patchAppliedBefore) {
        Write-Host "  Reusing existing patch state for $DependencyKey on $BuildBranch" -ForegroundColor DarkGray
    } else {
        Write-Host "  $DependencyKey already carries $patch" -ForegroundColor DarkGray
    }

    $paths = Get-PatchPaths $patch
    if ((@($paths).Count) -eq 0) {
        throw "Patch $patch does not declare any file paths."
    }
    Invoke-Git $repo (@('add','-A','--') + $paths) "git add $patch" | Out-Null

    $staged = @(Get-StagedPaths $repo)
    if ((@($staged).Count) -eq 0) { return }

    Write-Host "  Recording local build commit on $BuildBranch for $DependencyKey" -ForegroundColor Cyan
    Invoke-Git $repo @('commit','-m',$meta.Commit) "git commit $($meta.Commit)" | Out-Null
}

function Get-RecordedGitlink([string]$Repo, [string]$SubmodulePath) {
    $line = Get-GitText $Repo @('ls-tree','HEAD',$SubmodulePath) "git ls-tree $SubmodulePath" -AllowFailure
    if ($line -match '^160000 commit ([0-9a-f]{40})\s+') { return $Matches[1] }
    $null
}

function Sync-NestedBuildSubmodule($Entry) {
    $repoRelative = $Entry['ParentRepo']
    $nestedPath = $Entry['Path']
    $repo = Join-Path $Root $repoRelative
    $nestedRepo = Join-Path $repo $nestedPath
    $recorded = Get-RecordedGitlink $repo $nestedPath
    $current = Get-GitText $nestedRepo @('rev-parse','HEAD') "git rev-parse $nestedPath"
    if ($recorded -and $recorded -eq $current) { return }

    Write-Host "  Recording local $nestedPath pointer in $(Split-Path -Leaf $repoRelative) build branch" -ForegroundColor Cyan
    Invoke-Git $repo @('add','--',$nestedPath) "git add $nestedPath" | Out-Null
    $staged = @(Get-StagedPaths $repo)
    if ((@($staged).Count) -eq 0) { return }
    Invoke-Git $repo @('commit','-m',"Record local eMule build submodule: $nestedPath") "git commit $nestedPath" | Out-Null
}

function Get-VsWherePath {
    $path = Resolve-Tool @('vswhere.exe', 'vswhere')
    if ($path) { return $path }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }) {
        $installer = Join-Path $base 'Microsoft Visual Studio\Installer'
        $candidate = Resolve-FirstExisting @((Join-Path $installer 'vswhere.exe'))
        if ($candidate) { return $candidate }
    }
    $null
}

function Get-VsInfo {
    $vsWhere = Get-VsWherePath
    $candidates = @()
    if ($vsWhere) {
        $json = & $vsWhere -products * -format json -utf8 2>$null
        if ($LASTEXITCODE -eq 0 -and $json) {
            try {
                $candidates += ($json | ConvertFrom-Json | ForEach-Object { $_.installationPath })
            } catch {}
        }
    }
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }) {
        $root = Join-Path $base 'Microsoft Visual Studio\2022'
        if (Test-Path -LiteralPath $root) {
            $candidates += (Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
        }
    }
    $infos = $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Sort-Object -Unique | ForEach-Object {
        [pscustomobject]@{
            Root      = $_
            MSBuild   = Resolve-FirstExisting @((Join-Path $_ 'MSBuild\Current\Bin\MSBuild.exe'))
            DevEnv    = Resolve-FirstExisting @((Join-Path $_ 'Common7\IDE\devenv.exe'))
            VcVars64  = Resolve-FirstExisting @((Join-Path $_ 'VC\Auxiliary\Build\vcvars64.bat'))
            MfcHeader = Get-ChildItem -LiteralPath (Join-Path $_ 'VC\Tools\MSVC') -Directory -ErrorAction SilentlyContinue |
                Sort-Object Name -Descending |
                ForEach-Object { Join-Path $_.FullName 'atlmfc\include\afxwin.h' } |
                Where-Object { Test-Path -LiteralPath $_ } |
                Select-Object -First 1
        }
    }
    $candidate = $infos | Sort-Object @{ Expression = { -not $_.DevEnv } }, @{ Expression = { -not $_.MSBuild } }, Root | Select-Object -First 1
    if (-not $candidate) {
        return [pscustomobject]@{ VsWhere=$vsWhere; Root=$null; MSBuild=$null; DevEnv=$null; VcVars64=$null; MfcHeader=$null }
    }
    [pscustomobject]@{
        VsWhere   = $vsWhere
        Root      = $candidate.Root
        MSBuild   = $candidate.MSBuild
        DevEnv    = $candidate.DevEnv
        VcVars64  = $candidate.VcVars64
        MfcHeader = $candidate.MfcHeader
    }
}

function Get-SdkInfo {
    foreach ($base in @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }) {
        $root = Join-Path $base 'Windows Kits\10'
        $include = Join-Path $root 'Include'
        $lib = Join-Path $root 'Lib'
        if (-not (Test-Path -LiteralPath $include) -or -not (Test-Path -LiteralPath $lib)) { continue }
        $version = Get-ChildItem -LiteralPath $include -Directory -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { $_.Name } |
            Where-Object {
                (Test-Path -LiteralPath (Join-Path $include "$_\um\Windows.h")) -and
                (Test-Path -LiteralPath (Join-Path $lib "$_\um\x64\kernel32.lib"))
            } |
            Select-Object -First 1
        if ($version) { return [pscustomobject]@{ Root=$root; Version=$version } }
    }
    $null
}

function Add-Check($List, [string]$Status, [string]$Name, [string]$Detail) {
    $List.Add([pscustomobject]@{ Status=$Status; Name=$Name; Detail=$Detail }) | Out-Null
}

function Add-Checks($List, $Checks) {
    foreach ($check in @($Checks)) {
        if ($check) { $List.Add($check) | Out-Null }
    }
}

function Get-OutputPath([string]$Name, [string]$Configuration) {
    Join-Path $Root $Projects[$Name].Output[$Configuration]
}

function Get-GeneratedProjectProfile([string]$Name) {
    $profile = $GeneratedProjects[$Name]
    if (-not $profile) {
        throw "No generated project profile defined for $Name."
    }
    $profile
}

function Test-GeneratedProjectDefined([string]$Name) {
    $null -ne $GeneratedProjects[$Name]
}

function Test-WorkspaceTemplateDefined([string]$Name) {
    $templates = if ($Workspace.ContainsKey('Templates')) { $Workspace.Templates } else { $null }
    if (-not $templates) { return $false }
    $null -ne $templates[$Name]
}

function Test-WorkspacePaths([string[]]$RelativePaths) {
    foreach ($relativePath in $RelativePaths) {
        if (-not (Test-Path -LiteralPath (Get-WorkspacePath $relativePath))) {
            return $false
        }
    }
    return $true
}

function Test-GeneratedProjectReady([string]$Name) {
    Test-WorkspacePaths (Get-GeneratedProjectProfile $Name).ConfigureReady
}

function Get-GeneratedProjectBuildDir([string]$Name) {
    Get-WorkspacePath (Get-GeneratedProjectProfile $Name).Configure.Build
}

function Get-GeneratedProjectSourceDir([string]$Name) {
    Get-WorkspacePath (Get-GeneratedProjectProfile $Name).Configure.Source
}

function Get-GeneratedProjectArtifactName([string]$Name, [string]$Configuration) {
    $profile = Get-GeneratedProjectProfile $Name
    if (-not $profile.Contains('BuildArtifacts')) {
        throw "No build artifact mapping defined for $Name."
    }
    $artifactName = $profile.BuildArtifacts[$Configuration]
    if ([string]::IsNullOrWhiteSpace($artifactName)) {
        throw "No build artifact defined for $Name/$Configuration."
    }
    $artifactName
}

function Get-PackageProfile([string]$Configuration = 'Release') {
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
    $archiveName = if ($profile.Contains('ArchiveName')) { $profile.ArchiveName } else { $profile.Archive }
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
    $rootDir = Get-PackageRootDir $Configuration
    $cleanEntry = $Entry -replace '\\','/'
    "$rootDir/$cleanEntry"
}

function Get-DependencyBranchState([string]$DependencyKey) {
    $meta = $DependencyPatches[$DependencyKey]
    $repo = Join-Path $Root $meta.Repo
    $patch = if ($meta.Contains('Patch')) { $meta.Patch } else { $null }
    if (-not (Test-Path -LiteralPath $repo)) {
        return [pscustomobject]@{ Ready=$false; Detail='repo missing' }
    }

    $branch = Get-RepoBranch $repo
    $patchApplied = if ($patch) { Test-PatchApplied $repo $patch } else { $true }
    $patchLabel  = if ($patch) { if ($patchApplied) { 'present' } else { 'missing' } } else { 'baked-in' }
    $status = @(Get-RepoStatus $repo)
    $clean = (@($status).Count) -eq 0
    $ready = ($branch -eq $BuildBranch) -and $patchApplied -and $clean
    $detail = '{0}; patch {1}; {2}' -f $branch, $patchLabel, $(if ($clean) { 'clean' } else { 'dirty' })
    [pscustomobject]@{ Ready=$ready; Detail=$detail }
}

function Get-DependencyStatusRows {
    foreach ($key in $DependencyOrder) {
        $meta = $DependencyPatches[$key]
        $repo = Join-Path $Root $meta.Repo
        $patch = if ($meta.Contains('Patch')) { $meta.Patch } else { $null }
        if (-not (Test-Path -LiteralPath $repo)) {
            [pscustomobject]@{
                Name = $key
                Repo = $meta.Repo
                Branch = 'missing'
                Head = ''
                Patch = 'missing'
                Worktree = 'missing'
            }
            continue
        }

        $status = @(Get-RepoStatus $repo)
        [pscustomobject]@{
            Name = $key
            Repo = $meta.Repo
            Branch = Get-RepoBranch $repo
            Head = Get-RepoHeadShort $repo
            Patch = if (-not $patch) { 'baked-in' } elseif (Test-PatchApplied $repo $patch) { 'present' } else { 'missing' }
            Worktree = if ($status.Count -eq 0) { 'clean' } else { 'dirty' }
        }
    }
}

function Get-StatusRows {
    @(
        [pscustomobject]@{
            Name = 'eMule'
            Repo = 'eMule'
            Branch = Get-RepoBranch (Join-Path $Root 'eMule')
            Head = Get-RepoHeadShort (Join-Path $Root 'eMule')
            Patch = 'fork'
            Worktree = if ((@(Get-RepoStatus (Join-Path $Root 'eMule'))).Count -eq 0) { 'clean' } else { 'dirty' }
        }
    ) + @(Get-DependencyStatusRows)
}

function Get-ToolsContext {
    $git = Get-GitExe
    $perl = Get-PerlExe
    $cmake = Resolve-Tool @('cmake.exe', 'cmake')
    $vs = Get-VsInfo
    $sdk = Get-SdkInfo
    $identity = if ($git) { Get-GitIdentity $Root } else { $null }
    [pscustomobject]@{
        Git = $git
        Perl = $perl
        CMake = $cmake
        Vs = $vs
        Sdk = $sdk
        Identity = $identity
    }
}

function Get-ExpectedWorkspacePaths {
    $paths = [System.Collections.Generic.List[string]]::new()
    foreach ($path in @(
        'deps.psd1',
        'patches\cryptopp-CRYPTOPP_8_9_0.patch',

        'patches\miniupnpc-miniupnpc_2_3_3.patch',
        'patches\resizablelib-master.patch',
        'patches\zlib-v1.3.2.patch'
    )) {
        $paths.Add($path) | Out-Null
    }
    if (Test-WorkspaceTemplateDefined 'zlib') {
        $paths.Add($Workspace.Templates.zlib.Source) | Out-Null
    }
    if ($DependencyPatches.ContainsKey('mbedtls')) {
        $paths.Add('eMule-mbedtls') | Out-Null
        $paths.Add('patches\mbedtls-mbedtls-4.0.0.patch') | Out-Null
    }
    if ($DependencyPatches.ContainsKey('mbedtls-tf-psa-crypto')) {
        $paths.Add('patches\mbedtls-tf-psa-crypto-v1.0.0.patch') | Out-Null
    }
    if (Test-WorkspaceTemplateDefined 'mbedtls') {
        $paths.Add($Workspace.Templates.mbedtls.Source) | Out-Null
    }
    foreach ($name in @($Projects.Keys)) {
        $project = $Projects[$name]
        if ($project.Path) {
            $paths.Add($project.Path) | Out-Null
        }
        if ($project.Open) {
            $paths.Add($project.Open) | Out-Null
        }
    }
    foreach ($item in @((Get-PackageProfile 'Release').Include)) {
        if ($item.Source) {
            $paths.Add($item.Source) | Out-Null
        }
    }
    @($paths | Select-Object -Unique)
}

function Get-DependencySeverity([string]$Intent, [bool]$Ready) {
    if ($Ready) { return 'pass' }
    if ($Intent -in @('setup','repair','general','package','run-binary','clean-config')) { return 'warn' }
    return 'fail'
}

function Get-ConfigureSeverity([string]$Intent, [bool]$Ready) {
    if ($Ready) { return 'pass' }
    if ($Intent -in @('setup','repair','general','package','run-binary','clean-config')) { return 'warn' }
    return 'fail'
}

function Get-WorkspaceSeverity([string]$Intent, [int]$MissingCount) {
    if ($MissingCount -eq 0) { return 'pass' }
    if ($Intent -in @('setup','repair')) { return 'warn' }
    return 'fail'
}

function Get-ToolReport([string]$Intent, $ToolsContext) {
    $results = [System.Collections.Generic.List[object]]::new()
    $mbedtlsDefined = Test-GeneratedProjectDefined 'mbedtls'
    $mbedtlsConfigured = $mbedtlsDefined -and (Test-GeneratedProjectReady 'mbedtls')

    Add-Check $results 'pass' 'pwsh' "PowerShell $($PSVersionTable.PSVersion)"
    Add-Check $results ($ToolsContext.Git ? 'pass' : 'fail') 'git' ($ToolsContext.Git ? $ToolsContext.Git : 'not found on PATH')
    $perlStatus = if ($ToolsContext.Perl) {
        'pass'
    } elseif ($mbedtlsDefined -and -not $mbedtlsConfigured -and $Intent -in @('general','setup','repair','validate')) {
        'fail'
    } else {
        'warn'
    }
    $perlDetail = if ($ToolsContext.Perl) {
        $ToolsContext.Perl
    } elseif ($mbedtlsDefined) {
        'not found; required to regenerate mbedtls Visual Studio files'
    } else {
        'not found; no generated mbedtls profile in this stage'
    }
    Add-Check $results $perlStatus 'perl' $perlDetail
    Add-Check $results ($ToolsContext.CMake ? 'pass' : 'fail') 'cmake' ($ToolsContext.CMake ? $ToolsContext.CMake : 'not found on PATH')
    Add-Check $results ($ToolsContext.Vs.VsWhere ? 'pass' : 'warn') 'vswhere' ($ToolsContext.Vs.VsWhere ? $ToolsContext.Vs.VsWhere : 'not found; using install scan')
    Add-Check $results ($ToolsContext.Vs.Root ? 'pass' : 'fail') 'visual-studio' ($ToolsContext.Vs.Root ? $ToolsContext.Vs.Root : 'Visual Studio 2022 not found')
    Add-Check $results ($ToolsContext.Vs.MSBuild ? 'pass' : 'fail') 'msbuild' ($ToolsContext.Vs.MSBuild ? $ToolsContext.Vs.MSBuild : 'MSBuild.exe not found')
    Add-Check $results ($ToolsContext.Vs.VcVars64 ? 'pass' : 'fail') 'vcvars64' ($ToolsContext.Vs.VcVars64 ? $ToolsContext.Vs.VcVars64 : 'vcvars64.bat not found')
    Add-Check $results (($Intent -like 'open-*' -and -not $ToolsContext.Vs.DevEnv) ? 'fail' : ($ToolsContext.Vs.DevEnv ? 'pass' : 'warn')) 'devenv' ($ToolsContext.Vs.DevEnv ? $ToolsContext.Vs.DevEnv : 'devenv.exe not found')
    Add-Check $results ($ToolsContext.Vs.MfcHeader ? 'pass' : 'fail') 'mfc-atl' ($ToolsContext.Vs.MfcHeader ? $ToolsContext.Vs.MfcHeader : 'MFC/ATL headers not found')
    Add-Check $results ($ToolsContext.Sdk ? 'pass' : 'fail') 'windows-sdk' ($ToolsContext.Sdk ? "$($ToolsContext.Sdk.Version) @ $($ToolsContext.Sdk.Root)" : 'Windows 10 SDK not found')
    if ($ToolsContext.Git) {
        $hasIdentity = -not [string]::IsNullOrWhiteSpace($ToolsContext.Identity.Name) -and -not [string]::IsNullOrWhiteSpace($ToolsContext.Identity.Email)
        $identityStatus = if ($hasIdentity) {
            'pass'
        } elseif ($Intent -in @('setup','general','validate')) {
            'fail'
        } else {
            'warn'
        }
        $identityDetail = if ($hasIdentity) {
            "$($ToolsContext.Identity.Name) <$($ToolsContext.Identity.Email)>"
        } else {
            'missing git user.name and/or user.email'
        }
        Add-Check $results $identityStatus 'git-identity' $identityDetail
    }
    @($results)
}

function Get-WorkspaceReport([string]$Intent, $ToolsContext) {
    $results = [System.Collections.Generic.List[object]]::new()

    $missing = @(Get-ExpectedWorkspacePaths | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Root $_)) })
    Add-Check $results (Get-WorkspaceSeverity $Intent $missing.Count) 'workspace' (($missing.Count -eq 0) ? 'required paths present' : ('missing: ' + ($missing -join ', ')))

    foreach ($path in @('eMule\cryptopp','eMule\zlib','eMule\ResizableLib')) {
        $full = Join-Path $Root $path
        if ((Test-Path -LiteralPath $full) -and ((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Add-Check $results 'warn' 'obsolete-link' $path
        }
    }

    if ($ToolsContext.Git) {
        foreach ($key in $DependencyOrder) {
            $state = Get-DependencyBranchState $key
            $status = Get-DependencySeverity $Intent $state.Ready
            Add-Check $results $status "$key-branch" $state.Detail
        }
    }

    if (Test-GeneratedProjectDefined 'mbedtls') {
        $mbedtlsReady = Test-GeneratedProjectReady 'mbedtls'
        $mbedtlsConfigStatus = Get-ConfigureSeverity $Intent $mbedtlsReady
        Add-Check $results $mbedtlsConfigStatus 'mbedtls-configure' ($mbedtlsReady ? ((Get-GeneratedProjectProfile 'mbedtls').Configure.Build + ' ready') : 'missing or incomplete; run setup/repair')
    }

    $zlibConfigured = Test-GeneratedProjectReady 'zlib'
    $zlibConfigStatus = Get-ConfigureSeverity $Intent $zlibConfigured
    Add-Check $results $zlibConfigStatus 'zlib-configure' ($zlibConfigured ? ((Get-GeneratedProjectProfile 'zlib').ConfigureReady -join ', ') : 'missing; run setup/repair')
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
        $requiredEntries = @(Get-PackageEntryList $Configuration)
        $missingEntries = @($requiredEntries | Where-Object { $_ -notin $entries })
        if ($missingEntries.Count -gt 0) {
            return [pscustomobject]@{
                Status = 'fail'
                Name = 'package-archive'
                Detail = "missing entries $($missingEntries -join ', ') in $zip"
            }
        }
        [pscustomobject]@{
            Status = 'pass'
            Name = 'package-archive'
            Detail = "$zip => $($entries -join ', ')"
        }
    } catch {
        [pscustomobject]@{
            Status = 'fail'
            Name = 'package-archive'
            Detail = "$zip => $($_.Exception.Message)"
        }
    } finally {
        if ($archive) { $archive.Dispose() }
    }
}

function Get-BuildStateReport([string]$Intent, [string]$Configuration, [string]$ProjectName) {
    $results = [System.Collections.Generic.List[object]]::new()

    if ($Intent -in @('build-app','validate') -or ($Intent -eq 'build-project' -and $ProjectName -eq 'eMule')) {
        foreach ($dep in $BuildProjects) {
            $out = Get-OutputPath $dep $Configuration
            Add-Check $results ((Test-Path -LiteralPath $out) ? 'pass' : 'fail') "$dep-output" ((Test-Path -LiteralPath $out) ? $out : "missing: $out")
        }
    }

    if ($Intent -in @('run-binary','package','clean-config','validate')) {
        $exe = Get-OutputPath 'eMule' $Configuration
        $status = if (Test-Path -LiteralPath $exe) { 'pass' } elseif ($Intent -eq 'clean-config') { 'warn' } else { 'fail' }
        Add-Check $results $status 'emule-output' ((Test-Path -LiteralPath $exe) ? $exe : "missing: $exe")
    }

    if ($Intent -eq 'validate' -and $Configuration -eq 'Release') {
        Add-Checks $results (Get-PackageArchiveCheck $Configuration -Optional)
    }
    @($results)
}

function Get-EnvReport([string]$Intent, [string]$Configuration, [string]$ProjectName) {
    $toolsContext = Get-ToolsContext
    $results = [System.Collections.Generic.List[object]]::new()
    Add-Checks $results (Get-ToolReport $Intent $toolsContext)
    Add-Checks $results (Get-WorkspaceReport $Intent $toolsContext)
    Add-Checks $results (Get-BuildStateReport $Intent $Configuration $ProjectName)
    [pscustomobject]@{
        Results = @($results)
        Failed  = (@($results | Where-Object Status -eq 'fail')).Count
        Tools   = [pscustomobject]@{ Git=$toolsContext.Git; Perl=$toolsContext.Perl; CMake=$toolsContext.CMake; MSBuild=$toolsContext.Vs.MSBuild; DevEnv=$toolsContext.Vs.DevEnv }
    }
}

function Show-Report($Report) {
    foreach ($item in $Report.Results) {
        $color = @{ pass='Green'; warn='Yellow'; fail='Red' }[$item.Status]
        Write-Host ("[{0}] {1}: {2}" -f $item.Status.ToUpper(), $item.Name, $item.Detail) -ForegroundColor $color
    }
    if ($Report.Failed -gt 0) { throw 'Environment check failed.' }
}

function Invoke-Native([string]$Exe, [string[]]$ArgumentList, [string]$Label, [string]$WorkDir) {
    $old = $null
    if ($WorkDir) { $old = Get-Location; Set-Location -LiteralPath $WorkDir }
    try {
        & $Exe @ArgumentList
        if ($LASTEXITCODE -ne 0) { throw "$Label failed with exit code $LASTEXITCODE." }
    } finally {
        if ($old) { Set-Location $old }
    }
}

function Get-WorkspaceMutexName {
    $bytes = [Text.Encoding]::UTF8.GetBytes($Root.ToLowerInvariant())
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    "Local\eMule-build-$hash"
}

function Invoke-WithWorkspaceLock([string]$Label, [scriptblock]$Action) {
    $mutex = [Threading.Mutex]::new($false, (Get-WorkspaceMutexName))
    $acquired = $false
    try {
        $acquired = $mutex.WaitOne([TimeSpan]::FromHours(12))
        if (-not $acquired) {
            throw "Timed out waiting for workspace lock while running $Label."
        }
        & $Action
    } finally {
        if ($acquired) {
            $mutex.ReleaseMutex() | Out-Null
        }
        $mutex.Dispose()
    }
}

function Install-WorkspaceFile([string]$TemplateRelativePath, [string]$DestinationRelativePath) {
    $source = Get-WorkspacePath $TemplateRelativePath
    $destination = Get-WorkspacePath $DestinationRelativePath
    $parent = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $parent)) {
        $null = New-Item -ItemType Directory -Path $parent -Force
    }
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

function Install-MbedTlsWrapper {
    if (-not (Test-WorkspaceTemplateDefined 'mbedtls')) { return }
    $template = $Workspace.Templates.mbedtls
    Install-WorkspaceFile $template.Source $template.Destination
}

function Install-ZlibWrapper {
    if (-not (Test-WorkspaceTemplateDefined 'zlib')) { return }
    $template = $Workspace.Templates.zlib
    Install-WorkspaceFile $template.Source $template.Destination
}

function Normalize-MbedTlsGeneratedProjects([string]$BuildDir) {
    $sdkVersion = $Toolchain.WindowsTargetPlatformVersion
    foreach ($path in Get-ChildItem -LiteralPath $BuildDir -Recurse -Filter *.vcxproj -File -ErrorAction SilentlyContinue) {
        $content = [IO.File]::ReadAllText($path.FullName)
        $updated = [regex]::Replace($content, '<WindowsTargetPlatformVersion>[^<]+</WindowsTargetPlatformVersion>', "<WindowsTargetPlatformVersion>$sdkVersion</WindowsTargetPlatformVersion>")
        if ($updated -ne $content) {
            [IO.File]::WriteAllText($path.FullName, $updated)
        }
    }
}

function Invoke-GeneratedProjectConfigure([string]$Name, $EnvReport) {
    $profile = Get-GeneratedProjectProfile $Name
    $configure = $profile.Configure
    $args = @(
        '-S', (Get-GeneratedProjectSourceDir $Name),
        '-B', (Get-GeneratedProjectBuildDir $Name),
        '-G', $configure.Generator,
        '-A', $configure.Platform
    ) + @($configure.Arguments)

    if ($Name -eq 'mbedtls' -and $EnvReport.Tools.Perl) {
        $args += "-DPERL_EXECUTABLE=$($EnvReport.Tools.Perl)"
    }

    Invoke-Native -Exe $EnvReport.Tools.CMake -ArgumentList $args -Label "cmake configure $Name" -WorkDir $null
}

function Run-Setup {
    $envReport = Get-EnvReport 'setup' $Config $Project
    Show-Report $envReport
    Invoke-Native -Exe $envReport.Tools.Git -ArgumentList @('-C', $Root, 'submodule', 'update', '--init', '--recursive') -Label 'git submodule update' -WorkDir $null

    Ensure-BuildBranch 'eMule' 'eMule' $AppBuildBranch
    foreach ($key in $DependencyOrder) {
        Ensure-PatchCommit $key
    }
    foreach ($entry in $NestedSubmodules) {
        Sync-NestedBuildSubmodule $entry
    }

    if (Test-GeneratedProjectDefined 'mbedtls') {
        $mbedBuild = Get-GeneratedProjectBuildDir 'mbedtls'
        $mbedtlsConfiguredNow = $false
        if (-not (Test-GeneratedProjectReady 'mbedtls')) {
            Clean-MbedTlsGenerated
            Invoke-GeneratedProjectConfigure 'mbedtls' $envReport
            $mbedtlsConfiguredNow = $true
        }
        Install-MbedTlsWrapper
        if ($mbedtlsConfiguredNow) {
            Normalize-MbedTlsGeneratedProjects $mbedBuild
        }
    }

    if (-not (Test-GeneratedProjectReady 'zlib')) {
        Invoke-GeneratedProjectConfigure 'zlib' $envReport
    }
    Install-ZlibWrapper
}

function Ensure-Logs {
    if (-not (Test-Path -LiteralPath $LogsRoot)) { $null = New-Item -ItemType Directory -Path $LogsRoot -Force }
    if (-not (Test-Path -LiteralPath $RunLogs)) { $null = New-Item -ItemType Directory -Path $RunLogs -Force }
}

function Get-LogPath([string]$Name, [string]$Configuration) {
    Ensure-Logs
    Join-Path $RunLogs "$Name-$Configuration.log"
}

function Remove-GeneratedTarget([string]$RelativePath) {
    $path = Get-WorkspacePath $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { return }
    Remove-Item -LiteralPath $path -Recurse -Force
}

function Clean-MbedTlsGenerated {
    if (-not (Test-GeneratedProjectDefined 'mbedtls')) { return }
    foreach ($path in @((Get-GeneratedProjectProfile 'mbedtls').Cleanup)) {
        Remove-GeneratedTarget $path
    }
}

function Clean-Generated {
    foreach ($path in @($Workspace.Cleanup) + @((Get-GeneratedProjectProfile 'zlib').Cleanup)) {
        Remove-GeneratedTarget $path
    }
    Clean-MbedTlsGenerated
}

function Build-ProjectInternal($EnvReport, [string]$Name, [string]$Configuration) {
    $info = $Projects[$Name]
    $log = Get-LogPath $Name $Configuration
    if ($info.Kind -eq 'cmake') {
        $buildDir = Get-GeneratedProjectBuildDir $Name
        & $EnvReport.Tools.CMake --build $buildDir --config $Configuration --target zlibstatic *> $log
        if ($LASTEXITCODE -ne 0) { throw "$Name build failed. See $log" }
        $srcName = Get-GeneratedProjectArtifactName $Name $Configuration
        $src = Join-Path $buildDir "$Configuration\$srcName"
        $destDir = Split-Path -Parent (Get-OutputPath $Name $Configuration)
        if (-not (Test-Path -LiteralPath $destDir)) { $null = New-Item -ItemType Directory -Path $destDir -Force }
        Copy-Item -LiteralPath $src -Destination (Join-Path $destDir 'zlib.lib') -Force
        return
    }
    $target = if ($NoBuildClean) { 'Build' } else { 'Clean,Build' }
    & $EnvReport.Tools.MSBuild (Join-Path $Root $info.Path) "-target:$target" "/property:Configuration=$Configuration" /property:Platform=x64 /nologo /verbosity:minimal *> $log
    if ($LASTEXITCODE -ne 0) { throw "$Name build failed. See $log" }
}

function Build-Libs {
    $envReport = Get-EnvReport 'build-libs' $Config $Project
    Show-Report $envReport
    Ensure-Logs
    $cmake = $envReport.Tools.CMake
    $msbuild = $envReport.Tools.MSBuild
    $runLogs = $RunLogs
    $skipClean = $NoBuildClean.IsPresent
    $defs = $BuildProjects | ForEach-Object {
        $info = $Projects[$_]
        [pscustomobject]@{
            Name = $_
            Kind = $info.Kind
            Path = Join-Path $Root $info.Path
            Build = if ($info.Contains('Build')) { Get-GeneratedProjectBuildDir $_ } else { $null }
            Out = Split-Path -Parent (Get-OutputPath $_ $Config)
            Artifact = if ($info.Kind -eq 'cmake') { Get-GeneratedProjectArtifactName $_ $Config } else { $null }
        }
    }
    $throttleLimit = [Math]::Min([Math]::Max(1, @($defs).Count), [Math]::Max(1, [Environment]::ProcessorCount - 1))
    $results = $defs | ForEach-Object -Parallel {
        $def = $_
        $log = Join-Path $using:runLogs "$($def.Name)-$using:Config.log"
        try {
            if ($def.Kind -eq 'cmake') {
                & $using:cmake --build $def.Build --config $using:Config --target zlibstatic *> $log
                $code = $LASTEXITCODE
                if ($code -eq 0) {
                    if (-not (Test-Path -LiteralPath $def.Out)) { $null = New-Item -ItemType Directory -Path $def.Out -Force }
                    $src = Join-Path $def.Build ($using:Config + '\' + $def.Artifact)
                    Copy-Item -LiteralPath $src -Destination (Join-Path $def.Out 'zlib.lib') -Force
                }
            } else {
                $target = if ($using:skipClean) { 'Build' } else { 'Clean,Build' }
                & $using:msbuild $def.Path "-target:$target" "/property:Configuration=$using:Config" /property:Platform=x64 /nologo /verbosity:minimal *> $log
                $code = $LASTEXITCODE
            }
            [pscustomobject]@{ Name=$def.Name; Success=($code -eq 0); Log=$log; Message=if ($code -eq 0) { '' } else { "exit code $code" } }
        } catch {
            $_ | Out-File -FilePath $log -Append -Encoding utf8
            [pscustomobject]@{ Name=$def.Name; Success=$false; Log=$log; Message=$_.Exception.Message }
        }
    } -ThrottleLimit $throttleLimit
    $failed = $results | Where-Object { -not $_.Success }
    foreach ($r in $results | Sort-Object Name) {
        Write-Host ("[{0}] {1}{2}" -f ($(if ($r.Success) { 'PASS' } else { 'FAIL' })), $r.Name, $(if ($r.Success) { '' } else { ": $($r.Message). See $($r.Log)" })) -ForegroundColor ($(if ($r.Success) { 'Green' } else { 'Red' }))
    }
    if ($failed) { throw 'One or more library builds failed.' }
}

function Repair-Workspace {
    Run-Setup
    Build-Libs
    $r = Get-EnvReport 'build-app' $Config 'eMule'
    Show-Report $r
    Build-ProjectInternal $r 'eMule' $Config
}

function Get-PackageStageDir([string]$Configuration = 'Release') {
    Join-Path $RunLogs "package-$Configuration"
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

function New-PackageBuildInfo([string]$Configuration = 'Release') {
    $toolsContext = Get-ToolsContext
    $workspaceBranch = Get-RepoBranch $Root
    $workspaceCommit = Get-GitText $Root @('rev-parse', 'HEAD') 'git rev-parse HEAD'
    $sourceProject = (Get-PackageProfile $Configuration).SourceProject
    $sourceRepoPath = Split-Path -Parent (Get-OutputPath $sourceProject $Configuration)
    @(
        "PackageRoot: $(Get-PackageRootDir $Configuration)"
        "SourceProject: $sourceProject"
        "Configuration: $Configuration"
        "BuiltUtc: $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'))"
        "WorkspaceBranch: $workspaceBranch"
        "WorkspaceCommit: $workspaceCommit"
        "eMuleCommit: $(Get-RepoHeadShort (Get-WorkspacePath 'eMule'))"
        "Binary: $(Split-Path -Leaf (Get-OutputPath $sourceProject $Configuration))"
        "BinarySourceDir: $sourceRepoPath"
        "PowerShell: $($PSVersionTable.PSVersion)"
        "MSBuild: $($toolsContext.Vs.MSBuild)"
        "VisualStudio: $($toolsContext.Vs.Root)"
        "WindowsSdk: $($toolsContext.Sdk.Version)"
    ) -join [Environment]::NewLine
}

function New-PackageStage([string]$Configuration = 'Release') {
    Ensure-Logs
    $profile = Get-PackageProfile $Configuration
    $stageDir = Get-PackageStageDir $Configuration
    if (Test-Path -LiteralPath $stageDir) {
        Remove-Item -LiteralPath $stageDir -Recurse -Force
    }
    $packageRoot = Join-Path $stageDir $profile.RootDir
    $null = New-Item -ItemType Directory -Path $packageRoot -Force

    $sourceProject = $profile.SourceProject
    Copy-Item -LiteralPath (Get-OutputPath $sourceProject $Configuration) -Destination (Join-Path $packageRoot $profile.Entry) -Force

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

function Run-Binary {
    $envReport = Get-EnvReport 'run-binary' $Config 'eMule'
    Show-Report $envReport
    $dir = Join-Path $Root "eMule\srchybrid\x64\$Config"
    $source = Join-Path $dir 'emule.exe'
    $launch = {
        param([string]$Suffix, [bool]$Local)
        $target = Join-Path $dir ("eMule_{0}.exe" -f $Suffix)
        Copy-Item -LiteralPath $source -Destination $target -Force
        $psi = [Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $target
        $psi.UseShellExecute = $false
        if ($Local) {
            $home = Join-Path $Root 'tmp\Home'
            $psi.WorkingDirectory = $dir
            foreach ($path in @($home, (Join-Path $home 'AppData_Roaming'), (Join-Path $home 'AppData_Local'))) {
                if (-not (Test-Path -LiteralPath $path)) { $null = New-Item -ItemType Directory -Path $path -Force }
            }
            $psi.Environment['HOMEPATH'] = $home
            $psi.Environment['USERPROFILE'] = $home
            $psi.Environment['APPDATA'] = Join-Path $home 'AppData_Roaming'
            $psi.Environment['LOCALAPPDATA'] = Join-Path $home 'AppData_Local'
        } else {
            $psi.WorkingDirectory = $env:USERPROFILE
        }
        [Diagnostics.Process]::Start($psi) | Out-Null
    }
    switch ($Dirs) {
        'default' { & $launch (if ($Config -eq 'Debug') { 'debug_def' } else { 'def' }) $false }
        'local' { & $launch (if ($Config -eq 'Debug') { 'debug_loc' } else { 'loc' }) $true }
        'both' { & $launch (if ($Config -eq 'Debug') { 'debug_loc' } else { 'loc' }) $true; Start-Sleep -Seconds 10; & $launch (if ($Config -eq 'Debug') { 'debug_def' } else { 'def' }) $false }
    }
}

function Show-DependencyStatus {
    $report = Get-EnvReport 'general' $Config $Project
    Show-Report $report

    Get-StatusRows |
        Select-Object Name,Branch,Head,Patch,Worktree,Repo |
        Format-Table -AutoSize |
        Out-String -Width 200 |
        Write-Host
}

function Run-Validate {
    $report = Get-EnvReport 'validate' $Config 'eMule'
    Show-Report $report
    Get-StatusRows |
        Select-Object Name,Branch,Head,Patch,Worktree,Repo |
        Format-Table -AutoSize |
        Out-String -Width 200 |
        Write-Host
    Write-Host "Logs: $RunLogs" -ForegroundColor DarkGray
}

switch ($Command) {
    'env-check' { Show-Report (Get-EnvReport 'general' $Config $Project) }
    'dep-status' { Show-DependencyStatus }
    'validate' { Run-Validate }
    'setup' { Invoke-WithWorkspaceLock 'setup' { Run-Setup } }
    'repair' { Invoke-WithWorkspaceLock 'repair' { Repair-Workspace } }
    'build-libs' { Invoke-WithWorkspaceLock 'build-libs' { Build-Libs } }
    'build-app' {
        Invoke-WithWorkspaceLock 'build-app' {
            $Project = 'eMule'
            $r = Get-EnvReport 'build-app' $Config $Project
            Show-Report $r
            Build-ProjectInternal $r 'eMule' $Config
        }
    }
    'build-all' {
        Invoke-WithWorkspaceLock 'build-all' {
            Build-Libs
            $r = Get-EnvReport 'build-app' $Config 'eMule'
            Show-Report $r
            Build-ProjectInternal $r 'eMule' $Config
        }
    }
    'build-project' {
        Invoke-WithWorkspaceLock "build-project:$Project" {
            $intent = if ($Project -eq 'eMule') { 'build-app' } else { 'build-project' }
            $r = Get-EnvReport $intent $Config $Project
            Show-Report $r
            Build-ProjectInternal $r $Project $Config
        }
    }
    'open-solution' {
        $r = Get-EnvReport 'open-solution' $Config 'eMule'
        Show-Report $r
        Start-Process -FilePath $r.Tools.DevEnv -ArgumentList @(Join-Path $Root $Projects.eMule.Open) | Out-Null
    }
    'open-project' {
        $r = Get-EnvReport 'open-project' $Config $Project
        Show-Report $r
        Start-Process -FilePath $r.Tools.DevEnv -ArgumentList @(Join-Path $Root $Projects[$Project].Open) | Out-Null
    }
    'run-binary' { Run-Binary }
    'package' {
        Invoke-WithWorkspaceLock 'package' {
            $r = Get-EnvReport 'package' 'Release' 'eMule'
            Show-Report $r
            $zip = Get-PackagePath 'Release'
            $stageDir = New-PackageStage 'Release'
            New-PackageZip -SourceFile (Join-Path $stageDir (Get-PackageRootDir 'Release')) -DestinationZip $zip
        }
    }
    'clean-config' {
        Invoke-WithWorkspaceLock 'clean-config' {
            $r = Get-EnvReport 'clean-config' $Config 'eMule'
            Show-Report $r
            $path = Join-Path $Root "eMule\srchybrid\x64\$Config\config"
            if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
        }
    }
    'clean-generated' { Invoke-WithWorkspaceLock 'clean-generated' { Clean-Generated } }
}

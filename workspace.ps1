#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('env-check','dep-status','setup','build-libs','build-app','build-all','build-project','open-solution','open-project','run-binary','package','clean-config')]
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
$Logs = Join-Path $Root 'logs'
$BuildBranch = 'emule-build-v0.72a'
$DependencyPatches = [ordered]@{
    cryptopp = @{ Repo='eMule-cryptopp'; Patch='cryptopp-CRYPTOPP_8_9_0.patch'; Commit='Apply eMule build patch: cryptopp-CRYPTOPP_8_9_0.patch' }
    id3lib = @{ Repo='eMule-id3lib'; Patch='id3lib-v3.9.1.patch'; Commit='Apply eMule build patch: id3lib-v3.9.1.patch' }
    miniupnp = @{ Repo='eMule-miniupnp'; Patch='miniupnpc-miniupnpc_2_3_3.patch'; Commit='Apply eMule build patch: miniupnpc-miniupnpc_2_3_3.patch' }
    ResizableLib = @{ Repo='eMule-ResizableLib'; Patch='resizablelib-master.patch'; Commit='Apply eMule build patch: resizablelib-master.patch' }
    zlib = @{ Repo='eMule-zlib'; Patch='zlib-v1.3.2.patch'; Commit='Apply eMule build patch: zlib-v1.3.2.patch' }
    'mbedtls-tf-psa-crypto' = @{ Repo='eMule-mbedtls\tf-psa-crypto'; Patch='mbedtls-tf-psa-crypto-v1.0.0.patch'; Commit='Apply eMule build patch: mbedtls-tf-psa-crypto-v1.0.0.patch' }
    mbedtls = @{ Repo='eMule-mbedtls'; Patch='mbedtls-mbedtls-4.0.0.patch'; Commit='Apply eMule build patch: mbedtls-mbedtls-4.0.0.patch' }
}
$DependencyOrder = @('cryptopp','id3lib','miniupnp','ResizableLib','zlib','mbedtls-tf-psa-crypto','mbedtls')
$Projects = [ordered]@{
    cryptopp = @{ Kind='msbuild'; Path='eMule-cryptopp\cryptlib.vcxproj'; Output=@{ Release='eMule-cryptopp\x64\Release\cryptlib.lib'; Debug='eMule-cryptopp\x64\Debug\cryptlib.lib' }; Open='eMule-cryptopp\cryptlib.vcxproj' }
    id3lib = @{ Kind='msbuild'; Path='eMule-id3lib\libprj\id3lib.vcxproj'; Output=@{ Release='eMule-id3lib\libprj\x64\Release\id3lib.lib'; Debug='eMule-id3lib\libprj\x64\Debug\id3lib.lib' }; Open='eMule-id3lib\libprj\id3lib.vcxproj' }
    miniupnp = @{ Kind='msbuild'; Path='eMule-miniupnp\miniupnpc\msvc\miniupnpc.vcxproj'; Output=@{ Release='eMule-miniupnp\miniupnpc\msvc\x64\Release\miniupnpc.lib'; Debug='eMule-miniupnp\miniupnpc\msvc\x64\Debug\miniupnpc.lib' }; Open='eMule-miniupnp\miniupnpc\msvc\miniupnpc.vcxproj' }
    ResizableLib = @{ Kind='msbuild'; Path='eMule-ResizableLib\ResizableLib\ResizableLib.vcxproj'; Output=@{ Release='eMule-ResizableLib\ResizableLib\x64\Release\resizablelib.lib'; Debug='eMule-ResizableLib\ResizableLib\x64\Debug\resizablelib.lib' }; Open='eMule-ResizableLib\ResizableLib\ResizableLib.vcxproj' }
    zlib = @{ Kind='cmake'; Path='eMule-zlib'; Build='eMule-zlib\cmake-build'; Output=@{ Release='eMule-zlib\contrib\vstudio\vc\x64\Release\zlib.lib'; Debug='eMule-zlib\contrib\vstudio\vc\x64\Debug\zlib.lib' }; Open='eMule-zlib\contrib\vstudio\vc\zlib.vcxproj' }
    mbedtls = @{ Kind='msbuild'; Path='eMule-mbedtls\visualc\VS2017\mbedTLS.vcxproj'; Output=@{ Release='eMule-mbedtls\visualc\VS2017\x64\Release\mbedtls.lib'; Debug='eMule-mbedtls\visualc\VS2017\x64\Debug\mbedtls.lib' }; Open='eMule-mbedtls\visualc\VS2017\mbedTLS.vcxproj' }
    eMule = @{ Kind='msbuild'; Path='eMule\srchybrid\emule.vcxproj'; Output=@{ Release='eMule\srchybrid\x64\Release\emule.exe'; Debug='eMule\srchybrid\x64\Debug\emule.exe' }; Open='eMule\srchybrid\emule.sln' }
}

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

function Get-PatchPath([string]$PatchFile) {
    Join-Path $Root "patches\$PatchFile"
}

function Get-GitExe {
    Resolve-Tool @('git.exe', 'git')
}

function Invoke-Git([string]$Repo, [string[]]$ArgumentList, [string]$Label, [switch]$AllowFailure) {
    $git = Get-GitExe
    if (-not $git) { throw 'git not found on PATH.' }
    $output = & $git -C $Repo @ArgumentList 2>$null
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        throw "$Label failed with exit code $LASTEXITCODE."
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
    @((Invoke-Git $Repo @('status','--porcelain=v1','--untracked-files=all') 'git status') | Where-Object { $_ })
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

function Ensure-BuildBranch([string]$RepoRelative, [string]$Label) {
    $repo = Join-Path $Root $RepoRelative
    $currentBranch = Get-RepoBranch $repo
    if ($currentBranch -eq $BuildBranch) { return }

    $branchExists = Test-GitRef $repo "refs/heads/$BuildBranch"

    if ($branchExists) {
        Invoke-Git $repo @('switch', $BuildBranch) "git switch $BuildBranch" | Out-Null
        return
    }

    Invoke-Git $repo @('switch', '-c', $BuildBranch) "git switch -c $BuildBranch" | Out-Null
}

function Ensure-PatchCommit([string]$DependencyKey) {
    $meta = $DependencyPatches[$DependencyKey]
    $repo = Join-Path $Root $meta.Repo
    $patchAppliedBefore = Test-PatchApplied $repo $meta.Patch

    Ensure-BuildBranch $meta.Repo $DependencyKey

    if (-not (Test-PatchApplied $repo $meta.Patch)) {
        if (-not (Test-PatchCanApply $repo $meta.Patch)) {
            throw "$DependencyKey patch $($meta.Patch) cannot be applied cleanly."
        }
        Write-Host "  Applying $($meta.Patch)" -ForegroundColor Cyan
        Invoke-Git $repo @('apply','--3way','--ignore-whitespace',(Get-PatchPath $meta.Patch)) "git apply $($meta.Patch)" | Out-Null
    } elseif (-not $patchAppliedBefore) {
        Write-Host "  Reusing existing patch state for $DependencyKey on $BuildBranch" -ForegroundColor DarkGray
    } else {
        Write-Host "  $DependencyKey already carries $($meta.Patch)" -ForegroundColor DarkGray
    }

    $paths = Get-PatchPaths $meta.Patch
    if ((@($paths).Count) -eq 0) {
        throw "Patch $($meta.Patch) does not declare any file paths."
    }
    Invoke-Git $repo (@('add','-A','--') + $paths) "git add $($meta.Patch)" | Out-Null

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

function Sync-NestedBuildSubmodule {
    $repo = Join-Path $Root 'eMule-mbedtls'
    $nestedPath = 'tf-psa-crypto'
    $nestedRepo = Join-Path $repo $nestedPath
    $recorded = Get-RecordedGitlink $repo $nestedPath
    $current = Get-GitText $nestedRepo @('rev-parse','HEAD') 'git rev-parse tf-psa-crypto'
    if ($recorded -and $recorded -eq $current) { return }

    Write-Host '  Recording local tf-psa-crypto pointer in mbedtls build branch' -ForegroundColor Cyan
    Invoke-Git $repo @('add','--',$nestedPath) 'git add tf-psa-crypto' | Out-Null
    $staged = @(Get-StagedPaths $repo)
    if ((@($staged).Count) -eq 0) { return }
    Invoke-Git $repo @('commit','-m','Record local eMule build submodule: tf-psa-crypto') 'git commit tf-psa-crypto' | Out-Null
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

function Get-OutputPath([string]$Name, [string]$Configuration) {
    Join-Path $Root $Projects[$Name].Output[$Configuration]
}

function Get-DependencyBranchState([string]$DependencyKey) {
    $meta = $DependencyPatches[$DependencyKey]
    $repo = Join-Path $Root $meta.Repo
    if (-not (Test-Path -LiteralPath $repo)) {
        return [pscustomobject]@{ Ready=$false; Detail='repo missing' }
    }

    $branch = Get-RepoBranch $repo
    $patchApplied = Test-PatchApplied $repo $meta.Patch
    $status = @(Get-RepoStatus $repo)
    $clean = (@($status).Count) -eq 0
    $ready = ($branch -eq $BuildBranch) -and $patchApplied -and $clean
    $detail = '{0}; patch {1}; {2}' -f $branch, $(if ($patchApplied) { 'present' } else { 'missing' }), $(if ($clean) { 'clean' } else { 'dirty' })
    [pscustomobject]@{ Ready=$ready; Detail=$detail }
}

function Get-DependencyStatusRows {
    foreach ($key in $DependencyOrder) {
        $meta = $DependencyPatches[$key]
        $repo = Join-Path $Root $meta.Repo
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
            Patch = if (Test-PatchApplied $repo $meta.Patch) { 'present' } else { 'missing' }
            Worktree = if ($status.Count -eq 0) { 'clean' } else { 'dirty' }
        }
    }
}

function Get-EnvReport([string]$Intent, [string]$Configuration, [string]$ProjectName) {
    $results = [System.Collections.Generic.List[object]]::new()
    $git = Get-GitExe
    $cmake = Resolve-Tool @('cmake.exe', 'cmake')
    $tar = Resolve-Tool @('tar.exe', 'tar')
    $vs = Get-VsInfo
    $sdk = Get-SdkInfo
    $identity = if ($git) { Get-GitIdentity $Root } else { $null }
    $required = @(
        'eMule\srchybrid\emule.vcxproj',
        'eMule\srchybrid\emule.sln',
        'eMule-cryptopp\cryptlib.vcxproj',
        'eMule-id3lib\libprj\id3lib.vcxproj',
        'eMule-miniupnp\miniupnpc\msvc\miniupnpc.vcxproj',
        'eMule-ResizableLib\ResizableLib\ResizableLib.vcxproj',
        'eMule-zlib',
        'eMule-mbedtls',
        'patches\cryptopp-CRYPTOPP_8_9_0.patch',
        'patches\id3lib-v3.9.1.patch',
        'patches\miniupnpc-miniupnpc_2_3_3.patch',
        'patches\resizablelib-master.patch',
        'patches\zlib-v1.3.2.patch',
        'patches\mbedtls-mbedtls-4.0.0.patch',
        'patches\mbedtls-tf-psa-crypto-v1.0.0.patch'
    )

    Add-Check $results 'pass' 'pwsh' "PowerShell $($PSVersionTable.PSVersion)"
    Add-Check $results ($git ? 'pass' : 'fail') 'git' ($git ? $git : 'not found on PATH')
    Add-Check $results ($cmake ? 'pass' : 'fail') 'cmake' ($cmake ? $cmake : 'not found on PATH')
    $tarStatus = if ($tar) { 'pass' } elseif ($Intent -eq 'package') { 'fail' } else { 'warn' }
    Add-Check $results $tarStatus 'tar' ($tar ? $tar : 'not found on PATH')
    Add-Check $results ($vs.VsWhere ? 'pass' : 'warn') 'vswhere' ($vs.VsWhere ? $vs.VsWhere : 'not found; using install scan')
    Add-Check $results ($vs.Root ? 'pass' : 'fail') 'visual-studio' ($vs.Root ? $vs.Root : 'Visual Studio 2022 not found')
    Add-Check $results ($vs.MSBuild ? 'pass' : 'fail') 'msbuild' ($vs.MSBuild ? $vs.MSBuild : 'MSBuild.exe not found')
    Add-Check $results ($vs.VcVars64 ? 'pass' : 'fail') 'vcvars64' ($vs.VcVars64 ? $vs.VcVars64 : 'vcvars64.bat not found')
    Add-Check $results (($Intent -like 'open-*' -and -not $vs.DevEnv) ? 'fail' : ($vs.DevEnv ? 'pass' : 'warn')) 'devenv' ($vs.DevEnv ? $vs.DevEnv : 'devenv.exe not found')
    Add-Check $results ($vs.MfcHeader ? 'pass' : 'fail') 'mfc-atl' ($vs.MfcHeader ? $vs.MfcHeader : 'MFC/ATL headers not found')
    Add-Check $results ($sdk ? 'pass' : 'fail') 'windows-sdk' ($sdk ? "$($sdk.Version) @ $($sdk.Root)" : 'Windows 10 SDK not found')
    if ($git) {
        $hasIdentity = -not [string]::IsNullOrWhiteSpace($identity.Name) -and -not [string]::IsNullOrWhiteSpace($identity.Email)
        $identityStatus = if ($hasIdentity) {
            'pass'
        } elseif ($Intent -in @('setup','general')) {
            'fail'
        } else {
            'warn'
        }
        $identityDetail = if ($hasIdentity) {
            "$($identity.Name) <$($identity.Email)>"
        } else {
            'missing git user.name and/or user.email'
        }
        Add-Check $results $identityStatus 'git-identity' $identityDetail
    }

    $missing = @($required | Where-Object { -not (Test-Path -LiteralPath (Join-Path $Root $_)) })
    Add-Check $results (($missing.Count -eq 0) ? 'pass' : 'fail') 'workspace' (($missing.Count -eq 0) ? 'required paths present' : ('missing: ' + ($missing -join ', ')))

    foreach ($path in @('eMule\cryptopp','eMule\zlib','eMule\ResizableLib')) {
        $full = Join-Path $Root $path
        if ((Test-Path -LiteralPath $full) -and ((Get-Item -LiteralPath $full -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Add-Check $results 'warn' 'obsolete-link' $path
        }
    }

    if ($git) {
        foreach ($key in $DependencyOrder) {
            $state = Get-DependencyBranchState $key
            $status = if ($state.Ready) { 'pass' } elseif ($Intent -in @('setup','general')) { 'warn' } else { 'fail' }
            Add-Check $results $status "$key-branch" $state.Detail
        }
    }

    foreach ($pair in @(@('mbedtls-configure','eMule-mbedtls\visualc\VS2017\CMakeCache.txt'), @('zlib-configure','eMule-zlib\cmake-build\CMakeCache.txt'))) {
        $exists = Test-Path -LiteralPath (Join-Path $Root $pair[1])
        $status = if ($exists) { 'pass' } elseif ($Intent -eq 'setup' -or $Intent -eq 'general') { 'warn' } else { 'fail' }
        Add-Check $results $status $pair[0] ($exists ? $pair[1] : 'missing; run setup')
    }

    if ($Intent -eq 'build-app' -or ($Intent -eq 'build-project' -and $ProjectName -eq 'eMule')) {
        foreach ($dep in @('cryptopp','id3lib','miniupnp','ResizableLib','zlib','mbedtls')) {
            $out = Get-OutputPath $dep $Configuration
            Add-Check $results ((Test-Path -LiteralPath $out) ? 'pass' : 'fail') "$dep-output" ((Test-Path -LiteralPath $out) ? $out : "missing: $out")
        }
    }

    if ($Intent -in @('run-binary','package','clean-config')) {
        $exe = Get-OutputPath 'eMule' $Configuration
        $status = if (Test-Path -LiteralPath $exe) { 'pass' } elseif ($Intent -eq 'clean-config') { 'warn' } else { 'fail' }
        Add-Check $results $status 'emule-output' ((Test-Path -LiteralPath $exe) ? $exe : "missing: $exe")
    }

    [pscustomobject]@{
        Results = @($results)
        Failed  = (@($results | Where-Object Status -eq 'fail')).Count
        Tools   = [pscustomobject]@{ Git=$git; CMake=$cmake; Tar=$tar; MSBuild=$vs.MSBuild; DevEnv=$vs.DevEnv }
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

function Set-MbedTlsStaticRuntime([string]$BuildDir) {
    foreach ($rel in @('library\mbedtls.vcxproj','library\mbedx509.vcxproj','tf-psa-crypto\core\tfpsacrypto.vcxproj','tf-psa-crypto\drivers\builtin\builtin.vcxproj','tf-psa-crypto\drivers\everest\everest.vcxproj','tf-psa-crypto\drivers\p256-m\p256m.vcxproj')) {
        $path = Join-Path $BuildDir $rel
        $content = [IO.File]::ReadAllText($path)
        $updated = $content.Replace('<RuntimeLibrary>MultiThreadedDebugDLL</RuntimeLibrary>', '<RuntimeLibrary>MultiThreadedDebug</RuntimeLibrary>').Replace('<RuntimeLibrary>MultiThreadedDLL</RuntimeLibrary>', '<RuntimeLibrary>MultiThreaded</RuntimeLibrary>')
        if ($updated -ne $content) { [IO.File]::WriteAllText($path, $updated) }
    }
}

function Run-Setup {
    $envReport = Get-EnvReport 'setup' $Config $Project
    Show-Report $envReport
    Invoke-Native -Exe $envReport.Tools.Git -ArgumentList @('-C', $Root, 'submodule', 'update', '--init', '--recursive') -Label 'git submodule update' -WorkDir $null

    foreach ($key in $DependencyOrder) {
        Ensure-PatchCommit $key
    }
    Sync-NestedBuildSubmodule

    $mbedBuild = Join-Path $Root 'eMule-mbedtls\visualc\VS2017'
    if (-not (Test-Path -LiteralPath (Join-Path $mbedBuild 'CMakeCache.txt'))) {
        Invoke-Native -Exe $envReport.Tools.CMake -ArgumentList @('-S', (Join-Path $Root 'eMule-mbedtls'), '-B', $mbedBuild, '-G', 'Visual Studio 17 2022', '-A', 'x64', '-DENABLE_PROGRAMS=OFF', '-DENABLE_TESTING=OFF', '-DGEN_FILES=ON', '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug>') -Label 'cmake configure mbedtls' -WorkDir $null
    }
    Set-MbedTlsStaticRuntime $mbedBuild

    $zlibBuild = Join-Path $Root 'eMule-zlib\cmake-build'
    if (-not (Test-Path -LiteralPath (Join-Path $zlibBuild 'CMakeCache.txt'))) {
        Invoke-Native -Exe $envReport.Tools.CMake -ArgumentList @('-S', (Join-Path $Root 'eMule-zlib'), '-B', $zlibBuild, '-G', 'Visual Studio 17 2022', '-A', 'x64', '-DZLIB_BUILD_SHARED=OFF', '-DZLIB_BUILD_TESTING=OFF', '-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug>') -Label 'cmake configure zlib' -WorkDir $null
    }
}

function Ensure-Logs {
    if (-not (Test-Path -LiteralPath $Logs)) { $null = New-Item -ItemType Directory -Path $Logs }
}

function Build-ProjectInternal($EnvReport, [string]$Name, [string]$Configuration) {
    Ensure-Logs
    $info = $Projects[$Name]
    $log = Join-Path $Logs "$Name-$Configuration.log"
    if ($info.Kind -eq 'cmake') {
        $buildDir = Join-Path $Root $info.Build
        & $EnvReport.Tools.CMake --build $buildDir --config $Configuration --target zlibstatic *> $log
        if ($LASTEXITCODE -ne 0) { throw "$Name build failed. See $log" }
        $srcName = if ($Configuration -eq 'Debug') { 'zsd.lib' } else { 'zs.lib' }
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
    $skipClean = $NoBuildClean.IsPresent
    $defs = @('cryptopp','id3lib','miniupnp','ResizableLib','zlib','mbedtls') | ForEach-Object {
        $info = $Projects[$_]
        [pscustomobject]@{
            Name = $_
            Kind = $info.Kind
            Path = Join-Path $Root $info.Path
            Build = if ($info.Contains('Build')) { Join-Path $Root $info.Build } else { $null }
            Out = Split-Path -Parent (Get-OutputPath $_ $Config)
        }
    }
    $results = $defs | ForEach-Object -Parallel {
        $def = $_
        $log = Join-Path $using:Logs "$($def.Name)-$using:Config.log"
        try {
            if ($def.Kind -eq 'cmake') {
                & $using:cmake --build $def.Build --config $using:Config --target zlibstatic *> $log
                $code = $LASTEXITCODE
                if ($code -eq 0) {
                    if (-not (Test-Path -LiteralPath $def.Out)) { $null = New-Item -ItemType Directory -Path $def.Out -Force }
                    $src = Join-Path $def.Build ($using:Config + '\' + $(if ($using:Config -eq 'Debug') { 'zsd.lib' } else { 'zs.lib' }))
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
    } -ThrottleLimit 6
    $failed = $results | Where-Object { -not $_.Success }
    foreach ($r in $results | Sort-Object Name) {
        Write-Host ("[{0}] {1}{2}" -f ($(if ($r.Success) { 'PASS' } else { 'FAIL' })), $r.Name, $(if ($r.Success) { '' } else { ": $($r.Message). See $($r.Log)" })) -ForegroundColor ($(if ($r.Success) { 'Green' } else { 'Red' }))
    }
    if ($failed) { throw 'One or more library builds failed.' }
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

    $rows = @(
        [pscustomobject]@{
            Name = 'eMule'
            Repo = 'eMule'
            Branch = Get-RepoBranch (Join-Path $Root 'eMule')
            Head = Get-RepoHeadShort (Join-Path $Root 'eMule')
            Patch = 'fork'
            Worktree = if ((@(Get-RepoStatus (Join-Path $Root 'eMule'))).Count -eq 0) { 'clean' } else { 'dirty' }
        }
    ) + @(Get-DependencyStatusRows)

    $rows |
        Select-Object Name,Branch,Head,Patch,Worktree,Repo |
        Format-Table -AutoSize |
        Out-String -Width 200 |
        Write-Host
}

switch ($Command) {
    'env-check' { Show-Report (Get-EnvReport 'general' $Config $Project) }
    'dep-status' { Show-DependencyStatus }
    'setup' { Run-Setup }
    'build-libs' { Build-Libs }
    'build-app' {
        $Project = 'eMule'
        $r = Get-EnvReport 'build-app' $Config $Project
        Show-Report $r
        Build-ProjectInternal $r 'eMule' $Config
    }
    'build-all' {
        Build-Libs
        $r = Get-EnvReport 'build-app' $Config 'eMule'
        Show-Report $r
        Build-ProjectInternal $r 'eMule' $Config
    }
    'build-project' {
        $intent = if ($Project -eq 'eMule') { 'build-app' } else { 'build-project' }
        $r = Get-EnvReport $intent $Config $Project
        Show-Report $r
        Build-ProjectInternal $r $Project $Config
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
        $r = Get-EnvReport 'package' 'Release' 'eMule'
        Show-Report $r
        $zip = Join-Path $Root 'eMule0.72a-broadband_x64-snapshot.zip'
        if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
        Invoke-Native -Exe $r.Tools.Tar -ArgumentList @('-a','-c','-C',(Join-Path $Root 'eMule\srchybrid\x64\Release'),'-f',$zip,'eMule.exe') -Label 'tar package' -WorkDir $null
    }
    'clean-config' {
        $r = Get-EnvReport 'clean-config' $Config 'eMule'
        Show-Report $r
        $path = Join-Path $Root "eMule\srchybrid\x64\$Config\config"
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Recurse -Force }
    }
}

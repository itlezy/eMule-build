#Requires -Version 7.2
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('env-check','dep-status','validate','build-libs','build-app','build-tests','test','build-all','full')]
    [string]$Command,

    [string]$EmuleWorkspaceRoot,

    [ValidateSet('Release', 'Debug')]
    [string]$Config = 'Release',

    [ValidateSet('x64', 'ARM64')]
    [string]$Platform = 'x64',

    [string]$WorkspaceName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $false

$ScriptRoot = Split-Path -Parent $PSCommandPath
$Manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $ScriptRoot 'deps.psd1')
$Workspace = $Manifest.Workspace
$Dependencies = @($Workspace.Dependencies)
$AppRepo = $Workspace.AppRepo
$TestTargets = $AppRepo.TestTargets
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

function Resolve-Tool([string[]]$Names) {
    foreach ($name in $Names) {
        $command = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($command) {
            return $command.Source
        }
    }
    $null
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

function Get-RepoHead([string]$Repo) {
    ((Invoke-Git $Repo @('rev-parse','--short','HEAD') 'git rev-parse') -join "`n").Trim()
}

function Get-RepoStatus([string]$Repo) {
    @((Invoke-Git $Repo @('status','--short','--branch') 'git status') | Where-Object { $_ })
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

        [hashtable]$EnvironmentOverrides
    )

    $argumentList = @(
        $ProjectPath,
        '/m',
        '/nologo',
        "/t:$Target",
        "/p:Configuration=$Configuration",
        "/p:Platform=$Platform"
    ) + $ExtraProperties

    Invoke-Native (Get-MSBuildPath) $argumentList "MSBuild $(Split-Path -Leaf $ProjectPath)" -EnvironmentOverrides $EnvironmentOverrides
}

function Get-SelectedBuildTarget {
    [pscustomobject]@{
        Configuration = $Config
        Platform = $Platform
    }
}

function Assert-TestPlatformSupported {
    if ($Platform -ne 'x64') {
        throw "Shared test builds and test runs currently support x64 only. Requested platform: $Platform"
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
    @(Get-AppVariants | Where-Object { $_.Exists })
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

function Assert-AppLayout {
    $missing = @(Get-AppVariants | Where-Object { -not $_.Exists })
    if ($missing.Count -gt 0) {
        throw ("Missing app worktrees:`n{0}" -f (($missing | ForEach-Object { $_.Path }) -join [Environment]::NewLine))
    }

    foreach ($app in Get-AppVariants) {
        if ($app.CurrentBranch -ne $app.Branch) {
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

function Get-AppPropertyOverrides {
    @(
        "/p:WorkspaceRoot=$EmuleWorkspaceRoot\"
        "/p:CryptoPpRoot=$(Resolve-WorkspacePath 'repos\third_party\eMule-cryptopp')\"
        "/p:Id3libRoot=$(Resolve-WorkspacePath 'repos\third_party\eMule-id3lib')\"
        "/p:MbedTlsRoot=$(Resolve-WorkspacePath 'repos\third_party\eMule-mbedtls')\"
        "/p:MiniUpnpRoot=$(Resolve-WorkspacePath 'repos\third_party\eMule-miniupnp')\"
        "/p:ResizableLibRoot=$(Resolve-WorkspacePath 'repos\third_party\eMule-ResizableLib')\"
        "/p:ZlibRoot=$(Resolve-WorkspacePath 'repos\third_party\eMule-zlib')\"
    )
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
    if ($entry.Platform -eq 'ARM64') {
        Ensure-Arm64OverridesTargets
    }

    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-cryptopp\cryptlib.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties (Get-CryptoPpPlatformPropertyOverrides $entry.Platform) -Target Rebuild -EnvironmentOverrides (Get-CryptoPpEnvironmentOverrides $entry.Platform)
    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-id3lib\libprj\id3lib.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties (Get-Id3libPropertyOverrides $entry.Configuration $entry.Platform) -Target Rebuild
    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-miniupnp\miniupnpc\msvc\miniupnpc.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -Target Rebuild
    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-ResizableLib\ResizableLib\ResizableLib.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -Target Rebuild

    if ($entry.Configuration -eq 'Debug' -and $entry.Platform -eq 'x64') {
        Remove-StaleGeneratedArtifacts -RepoPath (Join-Path $thirdPartyRoot 'eMule-zlib') -Kind 'zlib'
        Remove-StaleGeneratedArtifacts -RepoPath (Join-Path $thirdPartyRoot 'eMule-mbedtls') -Kind 'mbedtls'
    }

    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-zlib\contrib\vstudio\vc\zlib.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties @("/p:WorkspaceCMakeExe=$cmakePath") -Target Rebuild
    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-mbedtls\visualc\VS2017\mbedTLS.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties @("/p:WorkspaceCMakeExe=$cmakePath", "/p:WorkspacePerlExe=$perlPath") -Target Rebuild
}

function Build-Apps {
    Assert-AppLayout
    $appProperties = Get-AppPropertyOverrides
    $entry = Get-SelectedBuildTarget
    foreach ($app in Get-ActiveApps) {
        $project = Join-Path $app.Path 'srchybrid\emule.vcxproj'
        $extraProperties = @($appProperties)
        $override = [Environment]::GetEnvironmentVariable($ToolsetOverrideVariable)
        if ($override) {
            $extraProperties += "/p:PlatformToolset=$override"
        }
        Invoke-MSBuildProject -ProjectPath $project -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties $extraProperties
    }
}

function Build-Tests {
    Assert-TestPlatformSupported
    $testRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tests
    $workspaceRoot = Get-WorkspaceRoot
    $appRoot = Resolve-AppVariantPath -Name $TestTargets.BuildVariant -RequireExists
    $scriptPath = Join-Path $testRepoRoot 'scripts\build-emule-tests.ps1'
    $entry = Get-SelectedBuildTarget

    Invoke-Native 'pwsh' @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $scriptPath,
        '-TestRepoRoot',
        $testRepoRoot,
        '-WorkspaceRoot',
        $workspaceRoot,
        '-AppRoot',
        $appRoot,
        '-Configuration',
        $entry.Configuration,
        '-Platform',
        $entry.Platform
    ) "build-emule-tests $($entry.Configuration)/$($entry.Platform)"
}

function Invoke-TestRuns {
    Assert-TestPlatformSupported
    $testRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tests
    $workspaceRoot = Get-WorkspaceRoot
    $bugfixAppRoot = Resolve-AppVariantPath -Name $TestTargets.CoverageVariant -RequireExists
    $buildAppRoot = Resolve-AppVariantPath -Name $TestTargets.OracleVariant -RequireExists
    $buildTag = Get-TestBuildTag -WorkspaceRoot $workspaceRoot -AppRoot $bugfixAppRoot
    $entry = Get-SelectedBuildTarget

    $coverageScriptPath = Join-Path $testRepoRoot 'scripts\run-native-coverage.ps1'
    $liveDiffScriptPath = Join-Path $testRepoRoot 'scripts\run-live-diff.ps1'

    $binaryPath = Join-Path $testRepoRoot ("build\{0}\{1}\{2}\emule-tests.exe" -f $buildTag, $entry.Platform, $entry.Configuration)
    if (-not (Test-Path -LiteralPath $binaryPath)) {
        throw "Built test executable not found: $binaryPath"
    }
    Invoke-Native $binaryPath @('--test-suite=parity') "parity tests $($entry.Configuration)/$($entry.Platform)" $testRepoRoot

    Invoke-Native 'pwsh' @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $coverageScriptPath,
        '-TestRepoRoot',
        $testRepoRoot,
        '-WorkspaceRoot',
        $workspaceRoot,
        '-AppRoot',
        $bugfixAppRoot,
        '-Configuration',
        $entry.Configuration,
        '-Platform',
        $entry.Platform
    ) 'native coverage'

    Invoke-Native 'pwsh' @(
        '-NoLogo',
        '-NoProfile',
        '-ExecutionPolicy',
        'Bypass',
        '-File',
        $liveDiffScriptPath,
        '-TestRepoRoot',
        $testRepoRoot,
        '-DevWorkspaceRoot',
        $workspaceRoot,
        '-DevAppRoot',
        $bugfixAppRoot,
        '-OracleWorkspaceRoot',
        $workspaceRoot,
        '-OracleAppRoot',
        $buildAppRoot,
        '-Configuration',
        $entry.Configuration,
        '-Platform',
        $entry.Platform
    ) 'live diff'
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

    $testRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tests
    foreach ($scriptPath in @(
        (Join-Path $testRepoRoot 'scripts\build-emule-tests.ps1'),
        (Join-Path $testRepoRoot 'scripts\run-native-coverage.ps1'),
        (Join-Path $testRepoRoot 'scripts\run-live-diff.ps1')
    )) {
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "Missing required test helper: $scriptPath"
        }
    }
}

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
    'test' {
        Invoke-TestRuns
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

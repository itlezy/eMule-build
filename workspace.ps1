#Requires -Version 7.6
[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $true)]
    [ValidateSet('env-check','dep-status','validate','build-libs','build-app','build-tests','test','live-diff','build-all','full')]
    [string]$Command,

    [string]$EmuleWorkspaceRoot,

    [ValidateSet('Release', 'Debug')]
    [string]$Config = 'Release',

    [ValidateSet('x64', 'ARM64')]
    [string]$Platform = 'x64',

    [ValidateSet('Full', 'Warnings', 'ErrorsOnly')]
    [string]$BuildOutputMode = 'ErrorsOnly',

    [string]$WorkspaceName,

    [string]$DevVariant,

    [string]$OracleVariant
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
        Write-Host ("Workspace busy: command '{0}' cannot start for {1}. Active owner: '{2}' (PID {3} on {4}, started {5})." -f $Command, $EmuleWorkspaceRoot, $metadata.command, $metadata.pid, $metadata.machine_name, $metadata.started_utc) -ForegroundColor Yellow
        return
    }

    Write-Host ("Workspace busy: command '{0}' cannot start for {1} because another eMule-build command already holds the workspace lock." -f $Command, $EmuleWorkspaceRoot) -ForegroundColor Yellow
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
    if ($BuildOutputMode -ne 'Full') {
        $null = Get-BuildLogDirectory
    }
}

function Add-BuildStepResult(
    [string]$StepName,
    [bool]$Succeeded,
    [string]$LogPath
) {
    if (-not (Get-Variable -Name BuildStepResults -Scope Script -ErrorAction SilentlyContinue)) {
        $script:BuildStepResults = [System.Collections.Generic.List[object]]::new()
    }

    $script:BuildStepResults.Add([pscustomobject]@{
        Name = $StepName
        Succeeded = $Succeeded
        LogPath = $LogPath
    }) | Out-Null
}

function Write-BuildStepSummary(
    [string]$StepName,
    [bool]$Succeeded,
    [string]$LogPath
) {
    if ($Succeeded) {
        if ($BuildOutputMode -eq 'Full') {
            return
        }

        Write-Host ("OK   {0}" -f $StepName) -ForegroundColor Green
        return
    }

    $line = "FAIL {0}" -f $StepName
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
    Write-Host ''
    Write-Host ("Build recap: {0}" -f $CommandName) -ForegroundColor Green
    Write-Host ("Steps: {0}" -f $steps.Count)
    Write-Host ("Failures: {0}" -f $failedCount)
    if ($BuildOutputMode -ne 'Full') {
        Write-Host ("Logs: {0}" -f (Get-BuildLogDirectory)) -ForegroundColor DarkGray
    }
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

        [hashtable]$EnvironmentOverrides,

        [string]$StepName = (Split-Path -LeafBase $ProjectPath)
    )

    $relativeProjectPath = [System.IO.Path]::GetRelativePath($EmuleWorkspaceRoot, $ProjectPath)
    $projectToken = Convert-ToFileToken ([System.IO.Path]::ChangeExtension($relativeProjectPath, $null))
    $logPath = $null
    $argumentList = @(
        $ProjectPath,
        '/m',
        '/nologo',
        "/t:$Target",
        "/p:Configuration=$Configuration",
        "/p:Platform=$Platform"
    ) + $ExtraProperties

    if ($BuildOutputMode -ne 'Full') {
        $logPath = Join-Path (Get-BuildLogDirectory) ("{0}-{1}-{2}-{3}.log" -f $projectToken, $Target.ToLowerInvariant(), $Configuration.ToLowerInvariant(), $Platform.ToLowerInvariant())
        $argumentList += @(
            ("/clp:{0}" -f $(switch ($BuildOutputMode) {
                'Warnings' { 'WarningsOnly' }
                'ErrorsOnly' { 'ErrorsOnly' }
            })),
            ("/flp:LogFile={0};Verbosity=normal;Encoding=UTF-8" -f $logPath)
        )
    }

    try {
        Invoke-Native (Get-MSBuildPath) $argumentList "MSBuild $(Split-Path -Leaf $ProjectPath)" -EnvironmentOverrides $EnvironmentOverrides
        Add-BuildStepResult -StepName $StepName -Succeeded $true -LogPath $logPath
        Write-BuildStepSummary -StepName $StepName -Succeeded $true -LogPath $logPath
    } catch {
        Add-BuildStepResult -StepName $StepName -Succeeded $false -LogPath $logPath
        Write-BuildStepSummary -StepName $StepName -Succeeded $false -LogPath $logPath
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
            Name = 'ResizableLib'
            Path = Join-Path $thirdPartyRoot ("eMule-ResizableLib\ResizableLib\{0}\{1}\ResizableLib.lib" -f $TargetPlatform, $Configuration)
        }
        [pscustomobject]@{
            Name = 'zlib'
            Path = Join-Path $thirdPartyRoot ("eMule-zlib\contrib\vstudio\vc\{0}\{1}\zlib.lib" -f $TargetPlatform, $Configuration)
        }
        [pscustomobject]@{
            Name = 'mbedtls'
            Path = Join-Path $thirdPartyRoot ("eMule-mbedtls\visualc\VS2017-{0}\library\{1}\mbedtls.lib" -f $TargetPlatform, $Configuration)
        }
        [pscustomobject]@{
            Name = 'mbedx509'
            Path = Join-Path $thirdPartyRoot ("eMule-mbedtls\visualc\VS2017-{0}\library\{1}\mbedx509.lib" -f $TargetPlatform, $Configuration)
        }
        [pscustomobject]@{
            Name = 'tfpsacrypto'
            Path = Join-Path $thirdPartyRoot ("eMule-mbedtls\visualc\VS2017-{0}\library\tfpsacrypto.lib" -f $TargetPlatform)
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
    if ($entry.Platform -eq 'ARM64') {
        Ensure-Arm64OverridesTargets
    }

    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-cryptopp\cryptlib.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties (Get-CryptoPpPlatformPropertyOverrides $entry.Platform) -EnvironmentOverrides (Get-CryptoPpEnvironmentOverrides $entry.Platform) -StepName 'DEP cryptopp'
    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-id3lib\libprj\id3lib.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties (Get-Id3libPropertyOverrides $entry.Configuration $entry.Platform) -StepName 'DEP id3lib'
    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-miniupnp\miniupnpc\msvc\miniupnpc.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -StepName 'DEP miniupnp'
    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-ResizableLib\ResizableLib\ResizableLib.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -StepName 'DEP ResizableLib'

    if ($entry.Configuration -eq 'Debug' -and $entry.Platform -eq 'x64') {
        Remove-StaleGeneratedArtifacts -RepoPath (Join-Path $thirdPartyRoot 'eMule-zlib') -Kind 'zlib'
        Remove-StaleGeneratedArtifacts -RepoPath (Join-Path $thirdPartyRoot 'eMule-mbedtls') -Kind 'mbedtls'
    }

    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-zlib\contrib\vstudio\vc\zlib.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties @("/p:WorkspaceCMakeExe=$cmakePath") -StepName 'DEP zlib'
    Invoke-MSBuildProject -ProjectPath (Join-Path $thirdPartyRoot 'eMule-mbedtls\visualc\VS2017\mbedTLS.vcxproj') -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties @("/p:WorkspaceCMakeExe=$cmakePath", "/p:WorkspacePerlExe=$perlPath") -StepName 'DEP mbedtls'
}

function Build-Apps {
    Assert-AppLayout
    $appProperties = Get-AppPropertyOverrides
    $entry = Get-SelectedBuildTarget
    Ensure-AppDependencyArtifacts -Configuration $entry.Configuration -TargetPlatform $entry.Platform
    foreach ($app in Get-ActiveApps) {
        $project = Join-Path $app.Path 'srchybrid\emule.vcxproj'
        $extraProperties = @($appProperties)
        $override = [Environment]::GetEnvironmentVariable($ToolsetOverrideVariable)
        if ($override) {
            $extraProperties += "/p:PlatformToolset=$override"
        }
        Invoke-MSBuildProject -ProjectPath $project -Configuration $entry.Configuration -Platform $entry.Platform -ExtraProperties $extraProperties -StepName ("APP {0}" -f $app.Name)
    }
}

function Build-Tests {
    $testRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tests
    $workspaceRoot = Get-WorkspaceRoot
    $appRoot = Resolve-AppVariantPath -Name $TestTargets.BuildVariant -RequireExists
    $scriptPath = Join-Path $testRepoRoot 'scripts\build-emule-tests.ps1'
    $entry = Get-SelectedBuildTarget
    $buildTag = Get-TestBuildTag -WorkspaceRoot $workspaceRoot -AppRoot $appRoot
    $logPath = if ($BuildOutputMode -ne 'Full') {
        Join-Path (Get-BuildLogDirectory) ("{0}-{1}-{2}.log" -f (Convert-ToFileToken ("emule-tests-{0}" -f $buildTag)), $entry.Configuration.ToLowerInvariant(), $entry.Platform.ToLowerInvariant())
    } else {
        $null
    }

    try {
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
            $entry.Platform,
            '-BuildOutputMode',
            $BuildOutputMode,
            '-BuildLogSessionStamp',
            (Get-BuildLogSessionStamp)
        ) "build-emule-tests $($entry.Configuration)/$($entry.Platform)"
        Add-BuildStepResult -StepName 'TEST emule-tests' -Succeeded $true -LogPath $logPath
    } catch {
        Add-BuildStepResult -StepName 'TEST emule-tests' -Succeeded $false -LogPath $logPath
        throw
    }
}

function Invoke-LiveDiffRuns {
    param(
        [string]$DevVariantName = $TestTargets.CoverageVariant,
        [string]$OracleVariantName = $TestTargets.OracleVariant
    )

    Assert-TestExecutionPlatformSupported
    $testRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tests
    $workspaceRoot = Get-WorkspaceRoot
    $devAppRoot = Resolve-AppVariantPath -Name $DevVariantName -RequireExists
    $oracleAppRoot = Resolve-AppVariantPath -Name $OracleVariantName -RequireExists
    $entry = Get-SelectedBuildTarget
    $liveDiffScriptPath = Join-Path $testRepoRoot 'scripts\run-live-diff.ps1'

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
        $devAppRoot,
        '-OracleWorkspaceRoot',
        $workspaceRoot,
        '-OracleAppRoot',
        $oracleAppRoot,
        '-Configuration',
        $entry.Configuration,
        '-Platform',
        $entry.Platform
    ) ("live diff {0} vs {1}" -f $DevVariantName, $OracleVariantName)
}

function Invoke-TestRuns {
    Assert-TestExecutionPlatformSupported
    $testRepoRoot = Resolve-WorkspacePath $Workspace.Repos.Tests
    $workspaceRoot = Get-WorkspaceRoot
    $devAppRoot = Resolve-AppVariantPath -Name $TestTargets.CoverageVariant -RequireExists
    $buildTag = Get-TestBuildTag -WorkspaceRoot $workspaceRoot -AppRoot $devAppRoot
    $entry = Get-SelectedBuildTarget

    $coverageScriptPath = Join-Path $testRepoRoot 'scripts\run-native-coverage.ps1'

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
        $devAppRoot,
        '-Configuration',
        $entry.Configuration,
        '-Platform',
        $entry.Platform
    ) 'native coverage'

    Invoke-LiveDiffRuns -DevVariantName $TestTargets.CoverageVariant -OracleVariantName $TestTargets.OracleVariant
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
        (Join-Path $testRepoRoot 'scripts\build-emule-tests.ps1'),
        (Join-Path $testRepoRoot 'scripts\run-native-coverage.ps1'),
        (Join-Path $testRepoRoot 'scripts\run-live-diff.ps1')
    )) {
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "Missing required test helper: $scriptPath"
        }
    }
}

if (-not (Acquire-WorkspaceCommandLock)) {
    exit 1
}

if ($Command -in @('build-libs', 'build-app', 'build-tests', 'build-all', 'full')) {
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
        'test' {
            Invoke-TestRuns
        }
        'live-diff' {
            Invoke-LiveDiffRuns -DevVariantName $(if ([string]::IsNullOrWhiteSpace($DevVariant)) { $TestTargets.CoverageVariant } else { $DevVariant }) -OracleVariantName $(if ([string]::IsNullOrWhiteSpace($OracleVariant)) { $TestTargets.OracleVariant } else { $OracleVariant })
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
    if ($Command -in @('build-libs', 'build-app', 'build-tests', 'build-all', 'full')) {
        Write-BuildCommandRecap -CommandName $Command
    }
    Release-WorkspaceCommandLock
}

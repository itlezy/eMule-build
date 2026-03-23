#Requires -Version 7.2
param(
    [ValidateSet('Release', 'Debug')]
    [string]$Config = 'Release'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

& (Join-Path $PSScriptRoot 'workspace.ps1') 'build-libs' '-Config' $Config
exit $LASTEXITCODE

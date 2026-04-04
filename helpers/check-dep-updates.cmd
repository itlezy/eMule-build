@ECHO OFF
CD /D %~dp0

pwsh -File check-dep-updates.ps1

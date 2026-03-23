@ECHO OFF
CD /D %~dp0
powershell -ExecutionPolicy Bypass -File 003_build_MSBuild_ALL_libs.ps1 -Config Debug
IF %ERRORLEVEL% NEQ 0 PAUSE

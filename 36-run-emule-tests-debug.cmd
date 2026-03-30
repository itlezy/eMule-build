@ECHO OFF
SETLOCAL
CD /D %~dp0

WHERE pwsh >NUL 2>NUL
IF ERRORLEVEL 1 (
  ECHO ERROR: PowerShell 7 is required. Install pwsh and ensure it is on PATH.
  EXIT /B 1
)

PWSH -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0eMule\helpers\helper-tests-build.ps1" -Configuration Debug -Platform x64 -Run %*
EXIT /B %ERRORLEVEL%

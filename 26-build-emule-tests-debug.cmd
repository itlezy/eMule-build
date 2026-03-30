@ECHO OFF
SETLOCAL
CD /D %~dp0

WHERE pwsh >NUL 2>NUL
IF ERRORLEVEL 1 (
  ECHO ERROR: PowerShell 7 is required. Install pwsh and ensure it is on PATH.
  EXIT /B 1
)

PWSH -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\scripts\build-emule-tests.ps1" -WorkspaceRoot "%~dp0" -Configuration Debug -Platform x64 %*
EXIT /B %ERRORLEVEL%

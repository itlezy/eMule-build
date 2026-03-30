@ECHO OFF
SETLOCAL
CD /D %~dp0
SET "WORKSPACE_ROOT=%~dp0."

WHERE pwsh >NUL 2>NUL
IF ERRORLEVEL 1 (
  ECHO ERROR: PowerShell 7 is required. Install pwsh and ensure it is on PATH.
  EXIT /B 1
)

PWSH -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0tests\scripts\run-live-diff.ps1" -DevWorkspaceRoot "%WORKSPACE_ROOT%" -OracleWorkspaceRoot "C:\prj\p2p\eMule\eMulebb\eMule-build-oracle" %*
EXIT /B %ERRORLEVEL%

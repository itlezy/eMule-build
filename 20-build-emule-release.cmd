@ECHO OFF
CALL "%~dp0workspace.cmd" build-app -Config Release %*
EXIT /B %ERRORLEVEL%


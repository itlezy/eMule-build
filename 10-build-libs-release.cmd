@ECHO OFF
CALL "%~dp0workspace.cmd" build-libs -Config Release %*
EXIT /B %ERRORLEVEL%


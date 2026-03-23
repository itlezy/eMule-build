@ECHO OFF
CALL "%~dp0workspace.cmd" build-libs -Config Debug %*
EXIT /B %ERRORLEVEL%


@ECHO OFF
CALL "%~dp0workspace.cmd" build-app -Config Debug
EXIT /B %ERRORLEVEL%

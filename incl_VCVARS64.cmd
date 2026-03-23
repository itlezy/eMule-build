@ECHO OFF
CALL "%~dp0workspace.cmd" env-check %*
EXIT /B %ERRORLEVEL%


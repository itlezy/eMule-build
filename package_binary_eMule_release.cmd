@ECHO OFF
CALL "%~dp0workspace.cmd" package %*
EXIT /B %ERRORLEVEL%


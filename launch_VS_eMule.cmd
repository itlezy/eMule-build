@ECHO OFF
CALL "%~dp0workspace.cmd" open-solution %*
EXIT /B %ERRORLEVEL%


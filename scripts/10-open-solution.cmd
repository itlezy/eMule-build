@ECHO OFF
CALL "%~dp0..\workspace.cmd" open-solution %*
EXIT /B %ERRORLEVEL%


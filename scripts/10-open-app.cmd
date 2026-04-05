@ECHO OFF
CALL "%~dp0..\workspace.cmd" open-app %*
EXIT /B %ERRORLEVEL%


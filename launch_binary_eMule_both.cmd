@ECHO OFF
CALL "%~dp0workspace.cmd" run-binary -Config Release -Dirs both %*
EXIT /B %ERRORLEVEL%


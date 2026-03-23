@ECHO OFF
CALL "%~dp0workspace.cmd" run-binary -Config Release -Dirs default %*
EXIT /B %ERRORLEVEL%


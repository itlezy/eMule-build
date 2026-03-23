@ECHO OFF
CALL "%~dp0workspace.cmd" run-binary -Config Debug -Dirs default %*
EXIT /B %ERRORLEVEL%


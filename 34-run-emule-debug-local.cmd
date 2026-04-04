@ECHO OFF
CALL "%~dp0workspace.cmd" run-binary -Config Debug -Dirs local %*
EXIT /B %ERRORLEVEL%


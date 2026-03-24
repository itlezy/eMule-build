@ECHO OFF
CALL "%~dp0workspace.cmd" run-binary -Config Release -Dirs local %*
EXIT /B %ERRORLEVEL%


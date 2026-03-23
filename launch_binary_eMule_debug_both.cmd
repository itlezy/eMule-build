@ECHO OFF
CALL "%~dp0workspace.cmd" run-binary -Config Debug -Dirs both %*
EXIT /B %ERRORLEVEL%


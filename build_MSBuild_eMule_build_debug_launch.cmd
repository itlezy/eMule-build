@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project eMule -Config Debug -NoBuildClean %*
IF ERRORLEVEL 1 EXIT /B %ERRORLEVEL%
START "" /MIN "%~dp0workspace.cmd" run-binary -Config Debug -Dirs local
EXIT /B 0


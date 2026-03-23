@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project eMule -Config Release -NoBuildClean %*
IF ERRORLEVEL 1 EXIT /B %ERRORLEVEL%
START "" /MIN "%~dp0workspace.cmd" run-binary -Config Release -Dirs default
START "" /MIN "%~dp0workspace.cmd" run-binary -Config Release -Dirs local
START "" /MIN "%~dp0workspace.cmd" package
EXIT /B 0


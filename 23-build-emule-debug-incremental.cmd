@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project eMule -Config Debug -NoBuildClean %*
EXIT /B %ERRORLEVEL%


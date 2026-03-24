@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project eMule -Config Release -NoBuildClean %*
EXIT /B %ERRORLEVEL%


@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project eMule -Config Debug %*
EXIT /B %ERRORLEVEL%


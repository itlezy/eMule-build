@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project eMule -Config Release %*
EXIT /B %ERRORLEVEL%


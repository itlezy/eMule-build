@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project cryptopp -Config Release %*
EXIT /B %ERRORLEVEL%


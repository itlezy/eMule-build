@ECHO OFF
CALL "%~dp0..\workspace.cmd" build-project -Project cryptopp -Config Release %*
EXIT /B %ERRORLEVEL%


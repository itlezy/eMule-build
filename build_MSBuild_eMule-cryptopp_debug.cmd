@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project cryptopp -Config Debug %*
EXIT /B %ERRORLEVEL%


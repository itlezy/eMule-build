@ECHO OFF
CALL "%~dp0..\workspace.cmd" open-project -Project cryptopp %*
EXIT /B %ERRORLEVEL%


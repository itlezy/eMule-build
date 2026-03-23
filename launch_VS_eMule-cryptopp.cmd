@ECHO OFF
CALL "%~dp0workspace.cmd" open-project -Project cryptopp %*
EXIT /B %ERRORLEVEL%


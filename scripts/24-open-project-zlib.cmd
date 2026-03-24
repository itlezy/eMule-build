@ECHO OFF
CALL "%~dp0..\workspace.cmd" open-project -Project zlib %*
EXIT /B %ERRORLEVEL%


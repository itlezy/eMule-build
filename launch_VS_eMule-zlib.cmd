@ECHO OFF
CALL "%~dp0workspace.cmd" open-project -Project zlib %*
EXIT /B %ERRORLEVEL%


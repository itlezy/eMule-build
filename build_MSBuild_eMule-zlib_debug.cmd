@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project zlib -Config Debug %*
EXIT /B %ERRORLEVEL%


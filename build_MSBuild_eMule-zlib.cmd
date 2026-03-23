@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project zlib -Config Release %*
EXIT /B %ERRORLEVEL%


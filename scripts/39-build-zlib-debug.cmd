@ECHO OFF
CALL "%~dp0..\workspace.cmd" build-project -Project zlib -Config Debug %*
EXIT /B %ERRORLEVEL%


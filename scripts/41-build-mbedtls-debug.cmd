@ECHO OFF
CALL "%~dp0..\workspace.cmd" build-project -Project mbedtls -Config Debug %*
EXIT /B %ERRORLEVEL%


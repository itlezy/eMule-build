@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project mbedtls -Config Debug %*
EXIT /B %ERRORLEVEL%


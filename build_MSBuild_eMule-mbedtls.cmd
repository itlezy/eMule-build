@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project mbedtls -Config Release %*
EXIT /B %ERRORLEVEL%


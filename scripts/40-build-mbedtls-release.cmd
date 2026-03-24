@ECHO OFF
CALL "%~dp0..\workspace.cmd" build-project -Project mbedtls -Config Release %*
EXIT /B %ERRORLEVEL%


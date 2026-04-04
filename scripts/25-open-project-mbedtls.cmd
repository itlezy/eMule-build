@ECHO OFF
CALL "%~dp0..\workspace.cmd" open-project -Project mbedtls %*
EXIT /B %ERRORLEVEL%


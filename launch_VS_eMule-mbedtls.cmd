@ECHO OFF
CALL "%~dp0workspace.cmd" open-project -Project mbedtls %*
EXIT /B %ERRORLEVEL%


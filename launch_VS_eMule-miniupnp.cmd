@ECHO OFF
CALL "%~dp0workspace.cmd" open-project -Project miniupnp %*
EXIT /B %ERRORLEVEL%


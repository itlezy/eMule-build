@ECHO OFF
CALL "%~dp0..\workspace.cmd" open-project -Project miniupnp %*
EXIT /B %ERRORLEVEL%


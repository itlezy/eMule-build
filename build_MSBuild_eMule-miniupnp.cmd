@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project miniupnp -Config Release %*
EXIT /B %ERRORLEVEL%


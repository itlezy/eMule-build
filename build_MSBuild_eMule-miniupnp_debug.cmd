@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project miniupnp -Config Debug %*
EXIT /B %ERRORLEVEL%


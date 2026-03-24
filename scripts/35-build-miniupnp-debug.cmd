@ECHO OFF
CALL "%~dp0..\workspace.cmd" build-project -Project miniupnp -Config Debug %*
EXIT /B %ERRORLEVEL%


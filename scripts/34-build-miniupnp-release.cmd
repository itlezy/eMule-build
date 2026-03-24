@ECHO OFF
CALL "%~dp0..\workspace.cmd" build-project -Project miniupnp -Config Release %*
EXIT /B %ERRORLEVEL%


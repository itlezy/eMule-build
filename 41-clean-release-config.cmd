@ECHO OFF
CALL "%~dp0workspace.cmd" clean-config -Config Release %*
EXIT /B %ERRORLEVEL%


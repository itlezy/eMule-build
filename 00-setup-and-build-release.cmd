@ECHO OFF
CALL "%~dp0workspace.cmd" setup
IF %ERRORLEVEL% NEQ 0 EXIT /B %ERRORLEVEL%
CALL "%~dp0workspace.cmd" build-all -Config Release
EXIT /B %ERRORLEVEL%

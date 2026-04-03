@ECHO OFF
CALL "%~dp0workspace.cmd" bootstrap -Config Release
EXIT /B %ERRORLEVEL%

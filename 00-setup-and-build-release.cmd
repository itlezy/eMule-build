@ECHO OFF
SETLOCAL
CD /D %~dp0

git submodule update --init --recursive
IF ERRORLEVEL 1 EXIT /B %ERRORLEVEL%

CALL "%~dp0workspace.cmd" setup
IF ERRORLEVEL 1 EXIT /B %ERRORLEVEL%

CALL "%~dp0workspace.cmd" build-libs -Config Release
IF ERRORLEVEL 1 EXIT /B %ERRORLEVEL%

CALL "%~dp0workspace.cmd" build-app -Config Release
IF ERRORLEVEL 1 EXIT /B %ERRORLEVEL%

CALL "%~dp0workspace.cmd" package
EXIT /B %ERRORLEVEL%

@ECHO OFF
CALL "%~dp0workspace.cmd" build-app -Config Debug
IF %ERRORLEVEL% NEQ 0 EXIT /B %ERRORLEVEL%
START "" /MIN %ComSpec% /C launch_binary_eMule_debug_localdirs.cmd

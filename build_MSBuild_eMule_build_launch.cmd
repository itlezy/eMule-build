@ECHO OFF
CALL "%~dp0workspace.cmd" build-app -Config Release
IF %ERRORLEVEL% NEQ 0 EXIT /B %ERRORLEVEL%
START "" /MIN %ComSpec% /C launch_binary_eMule_defaultdirs.cmd
START "" /MIN %ComSpec% /C launch_binary_eMule_localdirs.cmd
START "" /MIN %ComSpec% /C package_binary_eMule_release.cmd

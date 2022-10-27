@ECHO OFF

CD /D %~dp0

START "" /MIN %ComSpec% /C launch_binary_eMule_localdirs.cmd
SLEEP 10
START "" /MIN %ComSpec% /C launch_binary_eMule_defaultdirs.cmd
EXIT
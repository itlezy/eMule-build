@ECHO OFF

CD /D %~dp0

START "" %ComSpec% /C launch_binary_eMule_localdirs.cmd
SLEEP 5
START "" %ComSpec% /C launch_binary_eMule_defaultdirs.cmd
EXIT
@ECHO OFF

CD /D %~dp0

START "" %ComSpec% /C build_MSBuild_eMule.cmd

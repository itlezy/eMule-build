@ECHO OFF

DEL /Q %LOCALAPPDATA%\eMule\logs\*.log

CD /D %USERPROFILE%

START "" %~dp0eMule\srchybrid\x64\Release\eMule.exe

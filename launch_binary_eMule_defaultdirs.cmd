@ECHO OFF

DEL /Q %LOCALAPPDATA%\eMule\logs\*.log

CD /D %USERPROFILE%

COPY  /Y %~dp0eMule\srchybrid\x64\Release\eMule.exe  %~dp0eMule\srchybrid\x64\Release\eMule_def.exe
START "" /MIN /HIGH %~dp0eMule\srchybrid\x64\Release\eMule_def.exe

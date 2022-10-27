@ECHO OFF

DEL /Q %LOCALAPPDATA%\eMule\logs\*.log

CD /D %USERPROFILE%

COPY  /Y %~dp0eMule\srchybrid\x64\Debug\eMule.exe  %~dp0eMule\srchybrid\x64\Debug\eMule_debug_def.exe
START "" /MIN /HIGH %~dp0eMule\srchybrid\x64\Debug\eMule_debug_def.exe

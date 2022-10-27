@ECHO OFF

REM As you might have other eMule installations, this launcher script
REM ensures that this instance stays within a local tmp directory

CD /D %~dp0

SET CDD=%~dp0tmp
ECHO %CDD%

REM "Redirect" home directory to local tmp
SET HOMEPATH=%CDD%\Home
SET USERPROFILE=%CDD%\Home
SET APPDATA=%CDD%\Home\AppData_Roaming
SET LOCALAPPDATA=%CDD%\Home\AppData_Local

MD "%APPDATA%"
MD "%LOCALAPPDATA%"

CD /D eMule\srchybrid\x64\Debug\
COPY  /Y .\eMule.exe .\eMule_debug_loc.exe
START "" /MIN /HIGH .\eMule_debug_loc.exe

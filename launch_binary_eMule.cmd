CD /D %~dp0

SET CDD=%~dp0tmp
ECHO %CDD%

SET HOMEPATH=%CDD%\Home
SET USERPROFILE=%CDD%\Home
SET APPDATA=%CDD%\Home\AppData_Roaming
SET LOCALAPPDATA=%CDD%\Home\AppData_Local

MD "%APPDATA%"
MD "%LOCALAPPDATA%"

PAUSE

CD /D eMule\srchybrid\x64\Release\
START "" .\eMule.exe

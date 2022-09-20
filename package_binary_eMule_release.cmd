@ECHO OFF

SET PACK_NAME=eMule0.60d-broadband_x64-snapshot.zip

CD /D %~dp0

DEL %PACK_NAME%

CD /D eMule\srchybrid\x64\Release\
7za a -tzip %PACK_NAME% eMule.exe

MOVE %PACK_NAME% %~dp0

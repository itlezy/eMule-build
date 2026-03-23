@ECHO OFF
CD /D %~dp0

SET EXE=eMule\srchybrid\x64\Release\eMule.exe
SET PACK_NAME=eMule0.72a-broadband_x64-snapshot.zip

IF NOT EXIST "%EXE%" (
    ECHO ERROR: %EXE% not found. Build first.
    PAUSE & EXIT /B 1
)

DEL /F /Q "%PACK_NAME%" 2>NUL

tar -a -c -C "eMule\srchybrid\x64\Release" -f "%PACK_NAME%" eMule.exe
IF %ERRORLEVEL% NEQ 0 (
    ECHO ERROR: tar failed.
    PAUSE & EXIT /B 1
)

ECHO Packaged: %PACK_NAME%

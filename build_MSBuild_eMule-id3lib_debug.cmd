@ECHO OFF
CD /D %~dp0
CALL incl_VCVARS64.cmd
MSBuild eMule-id3lib\libprj\id3lib.vcxproj -target:Clean,Build /property:Configuration=Debug /property:Platform=x64
IF %ERRORLEVEL% NEQ 0 PAUSE

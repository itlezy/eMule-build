@ECHO OFF
CD /D %~dp0
CALL incl_VCVARS64.cmd
MSBuild eMule-mbedtls\visualc\VS2017\mbedTLS.vcxproj -target:Clean,Build /property:Configuration=Release /property:Platform=x64
IF %ERRORLEVEL% NEQ 0 PAUSE

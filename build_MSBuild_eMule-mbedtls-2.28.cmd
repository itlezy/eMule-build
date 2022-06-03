@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

CD eMule-mbedtls-2.28\visualc\VS2010

MSBuild mbedTLS.vcxproj -target:Clean,Build /property:Configuration=Release /property:Platform=x64

IF %ERRORLEVEL% NEQ 0 (
  PAUSE
) ELSE (
  CD /D %~dp0
  DEL /Q libs\mbedTLS*
  COPY eMule-mbedtls-2.28\visualc\VS2010\x64\Release\mbedTLS.lib     libs\
  COPY eMule-mbedtls-2.28\visualc\VS2010\x64\Release\mbedTLS.pdb     libs\
)

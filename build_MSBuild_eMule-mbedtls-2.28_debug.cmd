@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

CD eMule-mbedtls-2.28\visualc\VS2010

MSBuild mbedTLS.vcxproj -target:Clean,Build /property:Configuration=Debug /property:Platform=x64

IF %ERRORLEVEL% NEQ 0 (
  PAUSE
) ELSE (
  CD /D %~dp0
  DEL /Q libs_debug\mbedTLS*
  COPY eMule-mbedtls-2.28\visualc\VS2010\x64\Debug\mbedTLS.lib     libs_debug\
  COPY eMule-mbedtls-2.28\visualc\VS2010\x64\Debug\mbedTLS.pdb     libs_debug\
)

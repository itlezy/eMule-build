@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

CD eMule-cryptopp-8.4.0

MSBuild cryptlib.vcxproj -target:Clean,Build /property:Configuration=Debug /property:Platform=x64

IF %ERRORLEVEL% NEQ 0 (
  PAUSE
) ELSE (
  CD /D %~dp0
  DEL /Q libs_debug\cryptlib*
  COPY eMule-cryptopp-8.4.0\x64\Output\Debug\cryptlib.lib          libs_debug\
  COPY eMule-cryptopp-8.4.0\x64\Output\Debug\cryptlib.pdb          libs_debug\
)

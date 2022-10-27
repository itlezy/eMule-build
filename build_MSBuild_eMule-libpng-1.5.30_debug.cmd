@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

CD eMule-libpng-1.5.30\projects\vstudio

MSBuild vstudio.sln -target:Clean,Build /property:Configuration="Debug Library" /property:Platform=x64

IF %ERRORLEVEL% NEQ 0 (
  PAUSE
) ELSE (
  CD /D %~dp0
  DEL /Q libs_debug\libpng15*
  COPY "eMule-libpng-1.5.30\projects\vstudio\x64\Debug Library\libpng15.lib"    libs_debug\
  COPY "eMule-libpng-1.5.30\projects\vstudio\x64\Debug Library\libpng15.pdb"    libs_debug\
)

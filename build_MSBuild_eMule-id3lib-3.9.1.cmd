@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

CD eMule-id3lib-3.9.1\libprj

MSBuild id3lib.vcxproj -target:Clean,Build /property:Configuration=Release /property:Platform=x64

IF %ERRORLEVEL% NEQ 0 (
  PAUSE
) ELSE (
  CD /D %~dp0
  DEL /Q libs\id3lib*
  COPY eMule-id3lib-3.9.1\libprj\x64\Release\id3lib.lib              libs\
  COPY eMule-id3lib-3.9.1\libprj\x64\Release\id3lib.pdb              libs\
)

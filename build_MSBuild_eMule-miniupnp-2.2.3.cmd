@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

CD eMule-miniupnp-2.2.3\miniupnpc\msvc

MSBuild miniupnpc.vcxproj -target:Clean,Build /property:Configuration=Release /property:Platform=x64

IF %ERRORLEVEL% NEQ 0 (
  PAUSE
) ELSE (
  CD /D %~dp0
  DEL /Q libs\miniupnpc*
  COPY eMule-miniupnp-2.2.3\miniupnpc\msvc\x64\Release\miniupnpc.lib              libs\
  COPY eMule-miniupnp-2.2.3\miniupnpc\msvc\x64\Release\miniupnpc.pdb              libs\
)

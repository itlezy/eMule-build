@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

CD eMule-miniupnp-2.2.3\miniupnpc\msvc

MSBuild miniupnpc.vcxproj -target:Clean,Build /property:Configuration=Debug /property:Platform=x64

IF %ERRORLEVEL% NEQ 0 (
  PAUSE
) ELSE (
  CD /D %~dp0
  DEL /Q libs_debug\miniupnpc*
  COPY eMule-miniupnp-2.2.3\miniupnpc\msvc\x64\Debug\miniupnpc.lib              libs_debug\
  COPY eMule-miniupnp-2.2.3\miniupnpc\msvc\x64\Debug\miniupnpc.pdb              libs_debug\
)

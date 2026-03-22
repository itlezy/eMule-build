@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

CD eMule-zlib-1.2.12\contrib\vstudio\vc17

MSBuild zlibstat.vcxproj -target:Clean,Build /property:Configuration=Debug /property:Platform=x64 /property:PlatformToolset=%OVERLORD_PLATFORM_TOOLSET%

IF %ERRORLEVEL% NEQ 0 (
  EXIT /B %ERRORLEVEL%
) ELSE (
  CD /D %~dp0
  DEL /Q libs_debug\zlibstat*
  COPY eMule-zlib-1.2.12\contrib\vstudio\vc17\x64\ZlibStatDebug\zlibstat.lib              libs_debug\
  COPY eMule-zlib-1.2.12\contrib\vstudio\vc17\x64\ZlibStatDebug\zlibstat.pdb              libs_debug\
)

@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

CD eMule-zlib-1.2.12\contrib\vstudio\vc17

MSBuild zlibstat.vcxproj -target:Clean,Build /property:Configuration=Release /property:Platform=x64

IF %ERRORLEVEL% NEQ 0 (
  PAUSE
) ELSE (
  CD /D %~dp0
  DEL /Q libs\zlibstat*
  COPY eMule-zlib-1.2.12\contrib\vstudio\vc17\x64\ZlibStatRelease\zlibstat.lib              libs\
  COPY eMule-zlib-1.2.12\contrib\vstudio\vc17\x64\ZlibStatRelease\zlibstat.pdb              libs\
)

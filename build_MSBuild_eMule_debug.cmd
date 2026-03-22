@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

CD eMule\srchybrid

MSBuild emule.vcxproj -target:Clean,Build /property:Configuration=Debug /property:Platform=x64 /property:PlatformToolset=%OVERLORD_PLATFORM_TOOLSET%

IF %ERRORLEVEL% NEQ 0 (
  EXIT /B %ERRORLEVEL%
) ELSE (
  CD /D %~dp0
  ECHO ALL DONE
)

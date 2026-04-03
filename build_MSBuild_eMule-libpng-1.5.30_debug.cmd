@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

CD eMule-libpng-1.5.30\projects\vstudio

REM We only need the static libpng artifact for eMule linking here.
REM Building the whole solution also pulls pngtest/pngvalid, which expect a
REM separate zlib.lib name that this workspace does not produce.
REM Pass SolutionDir explicitly because the vcxproj imports zlib.props via
REM $(SolutionDir) even when built outside the .sln entrypoint.
MSBuild libpng\\libpng.vcxproj -target:Clean,Build /property:Configuration="Debug Library" /property:Platform=x64 /property:PlatformToolset=%EMULE_V060_PLATFORM_TOOLSET% /property:SolutionDir=%CD%\\

IF %ERRORLEVEL% NEQ 0 (
  EXIT /B %ERRORLEVEL%
) ELSE (
  CD /D %~dp0
  DEL /Q libs_debug\libpng15*
  COPY "eMule-libpng-1.5.30\projects\vstudio\x64\Debug Library\libpng15.lib"    libs_debug\
  COPY "eMule-libpng-1.5.30\projects\vstudio\x64\Debug Library\libpng15.pdb"    libs_debug\
)

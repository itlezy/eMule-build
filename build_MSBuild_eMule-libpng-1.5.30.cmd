@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

SET "ZLIB_PATH=%~dp0eMule-zlib-1.2.12"

CD eMule-libpng-1.5.30\projects\vstudio

MSBuild vstudio.sln -target:Clean,Build /property:Configuration="Release Library" /property:Platform=x64 /p:ZLibSrcDir="%ZLIB_PATH%"

IF %ERRORLEVEL% NEQ 0 (
  PAUSE
) ELSE (
  CD /D %~dp0
  DEL /Q libs\libpng15*
  COPY "eMule-libpng-1.5.30\projects\vstudio\x64\Release Library\libpng15.lib"    libs\
  COPY "eMule-libpng-1.5.30\projects\vstudio\x64\Release Library\libpng15.pdb"    libs\
)

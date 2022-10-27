@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

CD eMule-ResizableLib\ResizableLib

MSBuild ResizableLib.vcxproj -target:Clean,Build /property:Configuration="Debug Static" /property:Platform=x64

IF %ERRORLEVEL% NEQ 0 (
  PAUSE
) ELSE (
  CD /D %~dp0
  DEL /Q libs_debug\ResizableLib*
  COPY "eMule-ResizableLib\ResizableLib\x64\Debug Static\ResizableLib.lib"            libs_debug\
  COPY "eMule-ResizableLib\ResizableLib\x64\Debug Static\ResizableLib.pdb"            libs_debug\
)

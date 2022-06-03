@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

CD eMule-ResizableLib\ResizableLib

MSBuild ResizableLib.vcxproj -target:Clean,Build /property:Configuration="Release Static" /property:Platform=x64

IF %ERRORLEVEL% NEQ 0 (
  PAUSE
) ELSE (
  CD /D %~dp0
  DEL /Q libs\ResizableLib*
  COPY "eMule-ResizableLib\ResizableLib\x64\Release Static\ResizableLib.lib"            libs\
  COPY "eMule-ResizableLib\ResizableLib\x64\Release Static\ResizableLib.pdb"            libs\
)

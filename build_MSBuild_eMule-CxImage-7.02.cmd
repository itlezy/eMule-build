@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

CD eMule-CxImage-7.02\CxImage

MSBuild cximage.vcxproj -target:Clean,Build /property:Configuration=Release /property:Platform=x64

IF %ERRORLEVEL% NEQ 0 (
  PAUSE
) ELSE (
  CD /D %~dp0
  DEL /Q libs\cximage*
  COPY eMule-CxImage-7.02\CxImage\x64\Release\cximage.lib            libs\
  COPY eMule-CxImage-7.02\CxImage\x64\Release\cximage.pdb            libs\
)

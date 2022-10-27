@ECHO OFF

CD /D %~dp0

CALL incl_VCVARS64.cmd

CD eMule-CxImage-7.02\CxImage

MSBuild cximage.vcxproj -target:Clean,Build /property:Configuration=Debug /property:Platform=x64

IF %ERRORLEVEL% NEQ 0 (
  PAUSE
) ELSE (
  CD /D %~dp0
  DEL /Q libs_debug\cximage*
  COPY eMule-CxImage-7.02\CxImage\x64\Debug\cximage.lib            libs_debug\
  COPY eMule-CxImage-7.02\CxImage\x64\Debug\cximage.pdb            libs_debug\
)

@ECHO OFF

IF "%EMULE_V060_PLATFORM_TOOLSET%"=="" SET "EMULE_V060_PLATFORM_TOOLSET=v143"

SET "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
IF NOT EXIST "%VSWHERE%" SET "VSWHERE=%ProgramFiles%\Microsoft Visual Studio\Installer\vswhere.exe"
IF NOT EXIST "%VSWHERE%" (
  ECHO ERROR: vswhere.exe not found. Install Visual Studio 2022 with C++ build tools.
  EXIT /B 1
)

FOR /F "usebackq delims=" %%I IN (`"%VSWHERE%" -latest -products * -requires Microsoft.Component.MSBuild -property installationPath`) DO SET "VSINSTALLDIR=%%I"
IF "%VSINSTALLDIR%"=="" (
  ECHO ERROR: Unable to locate a Visual Studio installation with MSBuild.
  EXIT /B 1
)

CALL "%VSINSTALLDIR%\VC\Auxiliary\Build\vcvars64.bat"
EXIT /B %ERRORLEVEL%

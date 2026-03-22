@ECHO OFF

REM This ext-deps workspace is built on a VS2022-only machine.
REM Override the legacy v142 project setting at the MSBuild command line
REM so we can keep the checked-in oracle project files largely unchanged.
SET OVERLORD_PLATFORM_TOOLSET=v143

CALL "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"

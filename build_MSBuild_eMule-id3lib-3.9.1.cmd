@ECHO OFF

CALL "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"

CD /D %~dp0

CD eMule-id3lib-3.9.1\libprj

MSBuild id3lib.vcxproj -target:Clean,Build /property:Configuration=Release /property:Platform=x64

@ECHO OFF

CALL "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"

CD /D %~dp0

CD eMule-mbedtls-2.28\visualc\VS2010

MSBuild mbedTLS.vcxproj -target:Clean,Build /property:Configuration=Release /property:Platform=x64

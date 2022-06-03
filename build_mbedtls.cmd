CALL "%ProgramFiles(x86)%\Microsoft Visual Studio\2019\Community\VC\Auxiliary\Build\vcvars64.bat"

SET CMAKE=c:\prj\vcpkg\downloads\tools\cmake-3.22.2-windows\cmake-3.22.2-windows-i386\bin\cmake.exe
SET CMAKE_TOOLCHAIN_FILE_Z=c:\prj\vcpkg\scripts\buildsystems\vcpkg.cmake
SET CMAKE_PREFIX_PATH=c:\prj\vcpkg\installed\x64-windows-static\share

CD mbedtls

%CMAKE% -G "Ninja" -B build -DCMAKE_BUILD_TYPE=Release -DCMAKE_TOOLCHAIN_FILE="%CMAKE_TOOLCHAIN_FILE_Z%" -DVCPKG_TARGET_TRIPLET="x64-windows-static"

%CMAKE% --build build --parallel 4

@ECHO OFF
CD /D %~dp0

REM Auto-configure cmake if not done yet
IF NOT EXIST eMule-zlib\cmake-build\CMakeCache.txt (
    ECHO Configuring zlib cmake build...
    cmake -S eMule-zlib -B eMule-zlib\cmake-build ^
        -G "Visual Studio 17 2022" -A x64 ^
        -DZLIB_BUILD_SHARED=OFF ^
        -DZLIB_BUILD_TESTING=OFF ^
        "-DCMAKE_MSVC_RUNTIME_LIBRARY=MultiThreaded$<$<CONFIG:Debug>:Debug>"
    IF %ERRORLEVEL% NEQ 0 PAUSE & EXIT /B 1
)

cmake --build eMule-zlib\cmake-build --config Release --target zlibstatic
IF %ERRORLEVEL% NEQ 0 (PAUSE & EXIT /B 1)

IF NOT EXIST eMule-zlib\contrib\vstudio\vc\x64\Release MD eMule-zlib\contrib\vstudio\vc\x64\Release
COPY /Y eMule-zlib\cmake-build\Release\zs.lib eMule-zlib\contrib\vstudio\vc\x64\Release\zlib.lib

@ECHO OFF

CD /D %~dp0

ECHO Building libraries in dependency order (Debug)...
ECHO.

ECHO [1/8] Building zlib...
CALL build_MSBuild_eMule-zlib-1.2.12_debug.cmd
IF %ERRORLEVEL% NEQ 0 (
    ECHO ERROR: zlib build failed!
    PAUSE
    EXIT /B 1
)
ECHO.

ECHO [2/8] Building libpng...
CALL build_MSBuild_eMule-libpng-1.5.30_debug.cmd
IF %ERRORLEVEL% NEQ 0 (
    ECHO ERROR: libpng build failed!
    PAUSE
    EXIT /B 1
)
ECHO.

ECHO [3/8] Building CxImage...
CALL build_MSBuild_eMule-CxImage-7.02_debug.cmd
IF %ERRORLEVEL% NEQ 0 (
    ECHO ERROR: CxImage build failed!
    PAUSE
    EXIT /B 1
)
ECHO.

ECHO [4/8] Building cryptopp...
CALL build_MSBuild_eMule-cryptopp-8.4.0_debug.cmd
IF %ERRORLEVEL% NEQ 0 (
    ECHO ERROR: cryptopp build failed!
    PAUSE
    EXIT /B 1
)
ECHO.

ECHO [5/8] Building mbedtls...
CALL build_MSBuild_eMule-mbedtls-2.28_debug.cmd
IF %ERRORLEVEL% NEQ 0 (
    ECHO ERROR: mbedtls build failed!
    PAUSE
    EXIT /B 1
)
ECHO.

ECHO [6/8] Building miniupnp...
CALL build_MSBuild_eMule-miniupnp-2.2.3_debug.cmd
IF %ERRORLEVEL% NEQ 0 (
    ECHO ERROR: miniupnp build failed!
    PAUSE
    EXIT /B 1
)
ECHO.

ECHO [7/8] Building id3lib...
CALL build_MSBuild_eMule-id3lib-3.9.1_debug.cmd
IF %ERRORLEVEL% NEQ 0 (
    ECHO ERROR: id3lib build failed!
    PAUSE
    EXIT /B 1
)
ECHO.

ECHO [8/8] Building ResizableLib...
CALL build_MSBuild_eMule-ResizableLib_debug.cmd
IF %ERRORLEVEL% NEQ 0 (
    ECHO ERROR: ResizableLib build failed!
    PAUSE
    EXIT /B 1
)
ECHO.

ECHO All libraries built successfully!
PAUSE

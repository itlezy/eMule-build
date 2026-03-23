@ECHO OFF
CD /D %~dp0
START "" %ComSpec% /C build_MSBuild_eMule-cryptopp_debug.cmd
START "" %ComSpec% /C build_MSBuild_eMule-id3lib_debug.cmd
START "" %ComSpec% /C build_MSBuild_eMule-miniupnp_debug.cmd
START "" %ComSpec% /C build_MSBuild_eMule-ResizableLib_debug.cmd
START "" %ComSpec% /C build_MSBuild_eMule-zlib_debug.cmd
START "" %ComSpec% /C build_MSBuild_eMule-mbedtls_debug.cmd

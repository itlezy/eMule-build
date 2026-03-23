@ECHO OFF
CD /D %~dp0
START "" %ComSpec% /C build_MSBuild_eMule-cryptopp.cmd
START "" %ComSpec% /C build_MSBuild_eMule-id3lib.cmd
START "" %ComSpec% /C build_MSBuild_eMule-miniupnp.cmd
START "" %ComSpec% /C build_MSBuild_eMule-ResizableLib.cmd
START "" %ComSpec% /C build_MSBuild_eMule-zlib.cmd
START "" %ComSpec% /C build_MSBuild_eMule-mbedtls.cmd

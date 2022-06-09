@ECHO OFF

CD /D %~dp0

START "" %ComSpec% /C build_MSBuild_eMule-cryptopp-8.4.0.cmd
START "" %ComSpec% /C build_MSBuild_eMule-CxImage-7.02.cmd
START "" %ComSpec% /C build_MSBuild_eMule-id3lib-3.9.1.cmd
START "" %ComSpec% /C build_MSBuild_eMule-libpng-1.5.30.cmd
START "" %ComSpec% /C build_MSBuild_eMule-mbedtls-2.28.cmd
START "" %ComSpec% /C build_MSBuild_eMule-miniupnp-2.2.3.cmd
START "" %ComSpec% /C build_MSBuild_eMule-ResizableLib.cmd
START "" %ComSpec% /C build_MSBuild_eMule-zlib-1.2.12.cmd

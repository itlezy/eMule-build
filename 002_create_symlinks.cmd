@ECHO OFF

CD /D %~dp0

MKDIR libs libs_debug
MKDIR eMule-zz-deps-links

CD eMule-zz-deps-links

SET JUNC=mklink

REM CREATING SYMLINKS TO KEEP NICE NAMING OUTSIDE AND NOT CHANGE SOURCE CODE

%JUNC% /D cryptopp      ..\eMule-cryptopp-8.4.0
%JUNC% /D CxImage       ..\eMule-CxImage-7.02\CxImage
%JUNC% /D id3           ..\eMule-id3lib-3.9.1\include\id3
%JUNC% /D mbedtls       ..\eMule-mbedtls-2.28\include\mbedtls
%JUNC% /D miniupnpc     ..\eMule-miniupnp-2.2.3\miniupnpc\include
%JUNC% /D ResizableLib  ..\eMule-ResizableLib\ResizableLib
%JUNC% /D zlib          ..\eMule-zlib-1.2.12

@ECHO OFF

CD /D %~dp0

MKDIR eMule-zz-deps-links

CD eMule-zz-deps-links

SET JUNC=c:\bin\sysin\junction.exe

REM CREATING SYMLINKS TO KEEP NICE NAMING OUTSIDE AND NOT CHANGE SOURCE CODE

%JUNC% cryptopp      ..\eMule-cryptopp-8.4.0
%JUNC% CxImage       ..\eMule-CxImage-7.02\CxImage
%JUNC% id3           ..\eMule-id3lib-3.9.1\include\id3
%JUNC% mbedtls       ..\eMule-mbedtls-2.28\include\mbedtls
%JUNC% miniupnpc     ..\eMule-miniupnp-2.2.3\miniupnpc\include
%JUNC% ResizableLib  ..\eMule-ResizableLib\ResizableLib
%JUNC% zlib          ..\eMule-zlib-1.2.12

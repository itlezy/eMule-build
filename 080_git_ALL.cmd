@ECHO OFF

SET MSG=Debug configurations for libs

REM don't do this at home

CD %~dp0eMule-cryptopp-8.4.0  &&  CD  &&  git add -A  &&  git commit -a -m "%MSG%"  &&  git push
CD %~dp0eMule-CxImage-7.02    &&  CD  &&  git add -A  &&  git commit -a -m "%MSG%"  &&  git push
CD %~dp0eMule-id3lib-3.9.1    &&  CD  &&  git add -A  &&  git commit -a -m "%MSG%"  &&  git push
CD %~dp0eMule-libpng-1.5.30   &&  CD  &&  git add -A  &&  git commit -a -m "%MSG%"  &&  git push
CD %~dp0eMule-mbedtls-2.28    &&  CD  &&  git add -A  &&  git commit -a -m "%MSG%"  &&  git push
CD %~dp0eMule-miniupnp-2.2.3  &&  CD  &&  git add -A  &&  git commit -a -m "%MSG%"  &&  git push
CD %~dp0eMule-ResizableLib    &&  CD  &&  git add -A  &&  git commit -a -m "%MSG%"  &&  git push
CD %~dp0eMule-zlib-1.2.12     &&  CD  &&  git add -A  &&  git commit -a -m "%MSG%"  &&  git push
REM -- NOT THIS ONE -- CD %~dp0eMule                 &&  CD  &&  git add -A  &&  git commit -a -m "%MSG%"  &&  git push

CD %~dp0

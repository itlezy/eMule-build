@ECHO OFF

CD /D %~dp0

git clone https://github.com/itlezy/eMule-libpng.git "eMule-libpng-1.5.30"
CD "eMule-libpng-1.5.30"
git switch "1.5.30-eMule"

CD /D %~dp0

git clone https://github.com/itlezy/eMule-mbedtls.git "eMule-mbedtls-2.28"
CD "eMule-mbedtls-2.28"
git switch "mbedtls-2.28-eMule"

CD /D %~dp0

git clone https://github.com/itlezy/eMule-cryptopp.git "eMule-cryptopp-8.4.0"
CD "eMule-cryptopp-8.4.0"
git switch "CRYPTOPP_8_4_0-eMule"

CD /D %~dp0

git clone https://github.com/itlezy/eMule-zlib.git "eMule-zlib-1.2.12"
CD "eMule-zlib-1.2.12"
git switch "v1.2.12-eMule"

CD /D %~dp0

REM miniupnpc website http://miniupnp.free.fr/files/download.php?file=miniupnpc-2.2.3.tar.gz

git clone https://github.com/itlezy/eMule-miniupnp.git "eMule-miniupnp-2.2.3"
CD "eMule-miniupnp-2.2.3"
git switch "miniupnpc_2_2_3-eMule"

REM Inactive repos

CD /D %~dp0

git clone https://github.com/itlezy/eMule-CxImage.git "eMule-CxImage-7.02"
CD "eMule-CxImage-7.02"


CD /D %~dp0

git clone https://github.com/itlezy/eMule-id3lib.git "eMule-id3lib-3.9.1"
CD "eMule-id3lib-3.9.1"
git switch "v3.9.1"

CD /D %~dp0

git clone https://github.com/itlezy/eMule-ResizableLib.git
CD "eMule-ResizableLib"


CD /D %~dp0

git clone https://github.com/itlezy/eMule.git
CD "eMule"
git switch "v0.60d-build"

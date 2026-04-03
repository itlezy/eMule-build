@ECHO OFF

CD /D %~dp0

CALL :ENSURE_REPO "eMule-libpng-1.5.30" "https://github.com/itlezy/eMule-libpng.git" "1.5.30-eMule" || EXIT /B %ERRORLEVEL%
CALL :ENSURE_REPO "eMule-mbedtls-2.28" "https://github.com/itlezy/eMule-mbedtls.git" "mbedtls-2.28-eMule" || EXIT /B %ERRORLEVEL%
CALL :ENSURE_REPO "eMule-cryptopp-8.4.0" "https://github.com/itlezy/eMule-cryptopp.git" "CRYPTOPP_8_4_0-eMule" || EXIT /B %ERRORLEVEL%
CALL :ENSURE_REPO "eMule-zlib-1.2.12" "https://github.com/itlezy/eMule-zlib.git" "v1.2.12-eMule" || EXIT /B %ERRORLEVEL%
CALL :ENSURE_REPO "eMule-miniupnp-2.2.3" "https://github.com/itlezy/eMule-miniupnp.git" "miniupnpc_2_2_3-eMule" || EXIT /B %ERRORLEVEL%
CALL :ENSURE_REPO "eMule-CxImage-7.02" "https://github.com/itlezy/eMule-CxImage.git" "master" || EXIT /B %ERRORLEVEL%
CALL :ENSURE_REPO "eMule-id3lib-3.9.1" "https://github.com/itlezy/eMule-id3lib.git" "v3.9.1" || EXIT /B %ERRORLEVEL%
CALL :ENSURE_REPO "eMule-ResizableLib" "https://github.com/itlezy/eMule-ResizableLib.git" "master" || EXIT /B %ERRORLEVEL%
CALL :ENSURE_REPO "eMule" "https://github.com/itlezy/eMule.git" "" || EXIT /B %ERRORLEVEL%
ECHO Clone/update pass complete. Run `workspace.cmd setup` next.
EXIT /B 0

:ENSURE_REPO
SET "TARGET=%~1"
SET "URL=%~2"
SET "BRANCH=%~3"
IF NOT EXIST "%TARGET%\.git" (
  git clone "%URL%" "%TARGET%" || EXIT /B %ERRORLEVEL%
)
git -C "%TARGET%" fetch --all --prune || EXIT /B %ERRORLEVEL%
IF NOT "%BRANCH%"=="" git -C "%TARGET%" switch "%BRANCH%" || EXIT /B %ERRORLEVEL%
EXIT /B 0

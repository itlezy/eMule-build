@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project id3lib -Config Release %*
EXIT /B %ERRORLEVEL%


@ECHO OFF
CALL "%~dp0..\workspace.cmd" build-project -Project id3lib -Config Debug %*
EXIT /B %ERRORLEVEL%


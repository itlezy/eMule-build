@ECHO OFF
CALL "%~dp0..\workspace.cmd" open-project -Project id3lib %*
EXIT /B %ERRORLEVEL%


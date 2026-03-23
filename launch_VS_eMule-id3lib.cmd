@ECHO OFF
CALL "%~dp0workspace.cmd" open-project -Project id3lib %*
EXIT /B %ERRORLEVEL%


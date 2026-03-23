@ECHO OFF
CALL "%~dp0workspace.cmd" open-project -Project ResizableLib %*
EXIT /B %ERRORLEVEL%


@ECHO OFF
CALL "%~dp0..\workspace.cmd" open-project -Project ResizableLib %*
EXIT /B %ERRORLEVEL%


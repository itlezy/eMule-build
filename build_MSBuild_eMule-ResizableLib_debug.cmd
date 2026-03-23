@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project ResizableLib -Config Debug %*
EXIT /B %ERRORLEVEL%


@ECHO OFF
CALL "%~dp0workspace.cmd" build-project -Project ResizableLib -Config Release %*
EXIT /B %ERRORLEVEL%


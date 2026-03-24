@ECHO OFF
CALL "%~dp0..\workspace.cmd" build-project -Project ResizableLib -Config Release %*
EXIT /B %ERRORLEVEL%


@ECHO OFF
ECHO 001_clone_git_repos.cmd is deprecated.
ECHO Use workspace.cmd bootstrap -Config Release for the supported one-command flow.
CALL "%~dp0workspace.cmd" setup
EXIT /B %ERRORLEVEL%

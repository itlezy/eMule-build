@ECHO OFF
PUSHD "%~dp0..\.." || EXIT /B 1
python -m pip install -e .[dev] || EXIT /B 1
python -m pytest || EXIT /B 1
POPD

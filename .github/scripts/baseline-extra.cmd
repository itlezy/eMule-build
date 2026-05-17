@ECHO OFF
python -m pip install -e .[dev] || EXIT /B 1
python -m pytest || EXIT /B 1

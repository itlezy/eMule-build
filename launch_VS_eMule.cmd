@ECHO OFF

CD /D %~dp0

CD eMule
git pull

CD /D %~dp0
START "" eMule\srchybrid\emule.sln

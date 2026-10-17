
@echo off
set /p msg=Enter commit message: 

git add -A
if errorlevel 1 exit /b 1

git commit -m "%msg%"
if errorlevel 1 exit /b 1

git push
if errorlevel 1 exit /b 1

echo.
echo Successfully pushed to GitHub!

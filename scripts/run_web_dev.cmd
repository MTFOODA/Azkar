@echo off
rem Runs the Web launcher without depending on the PowerShell execution policy.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_web_dev.ps1" %*
exit /b %ERRORLEVEL%

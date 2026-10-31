@echo off
rem Runs the Android launcher without depending on the PowerShell execution policy.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0run_android_dev.ps1" %*
exit /b %ERRORLEVEL%

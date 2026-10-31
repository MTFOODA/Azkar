@echo off
rem Builds a debug APK that always carries the development Supabase configuration.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0check_supabase_dev_config.ps1"
if errorlevel 1 exit /b 1
pushd "%~dp0.."
flutter build apk --debug --dart-define-from-file=config/dev.json %*
set RESULT=%ERRORLEVEL%
popd
exit /b %RESULT%

@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\update_coop.ps1"
if errorlevel 1 echo Co-op update failed. Send the error shown above.
pause

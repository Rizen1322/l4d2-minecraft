@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-BlockSandbox.ps1"
if errorlevel 1 pause

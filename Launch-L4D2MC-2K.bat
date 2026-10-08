@echo off
setlocal
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Launch-Minecraft.ps1" -Width 2560 -Height 1440 -Borderless %*
if errorlevel 1 pause

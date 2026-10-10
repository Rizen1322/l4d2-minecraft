@echo off
rem Double-click this file. It finds L4D2, Minecraft and Java automatically,
rem installs everything and writes setup-log.txt next to itself.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Auto-Setup-L4D2MC.ps1"
if errorlevel 1 start "" notepad "%~dp0setup-log.txt"

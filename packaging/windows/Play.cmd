@echo off
rem Starts a local server and a practice match. Arguments are passed to Play.ps1.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Play.ps1" %*

@echo off
rem Claude Usage Widget launcher
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0ClaudeUsage.ps1"

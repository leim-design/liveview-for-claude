@echo off
rem LiveView for Claude - disable autostart
reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v ClaudeUsageWidget /f >nul 2>&1
if %errorlevel%==0 (
    echo.
    echo  [OK] Autostart disabled.
) else (
    echo.
    echo  [INFO] Autostart was not enabled.
)
echo.
pause

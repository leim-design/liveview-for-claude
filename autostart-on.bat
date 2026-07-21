@echo off
rem LiveView for Claude - run automatically at Windows login
reg add "HKCU\Software\Microsoft\Windows\CurrentVersion\Run" /v ClaudeUsageWidget /t REG_SZ /d "powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"%~dp0ClaudeUsage.ps1\"" /f >nul 2>&1
if %errorlevel%==0 (
    echo.
    echo  [OK] Autostart enabled. LiveView will launch at your next login.
    echo  Run autostart-off.bat to disable.
) else (
    echo.
    echo  [FAIL] Could not register. Try right-click - Run as administrator.
)
echo.
pause

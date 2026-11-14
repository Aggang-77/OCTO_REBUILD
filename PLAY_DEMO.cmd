@echo off
cd /d "%~dp0"
echo OCTO / Controls v1.0 / Fast renderer (no jelly shader)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run-demo.ps1" -Animals 2
if errorlevel 1 (
    echo.
    echo Demo could not start. Review the error above.
    pause
)

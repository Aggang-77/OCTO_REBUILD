@echo off
cd /d "%~dp0"
if exist "%~dp0game\assets\Octopus_GameReady_v5.glb" (
    echo Starting jelly demo using the original GameReady model...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run-demo.ps1" -Animals 2
) else (
    echo Original GameReady GLB not found. Starting procedural jelly demo instead...
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\run-demo.ps1" -Animals 2 -Procedural
)
if errorlevel 1 (
    echo.
    echo Demo could not start. Review the error above.
    pause
)

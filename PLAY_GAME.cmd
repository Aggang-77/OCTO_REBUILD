@echo off
setlocal
cd /d "%~dp0"
if not exist "native\octo\octo_game_server.exe" (
    echo Build the octopus engine first: powershell -File tools\build_octopus.ps1
    pause
    exit /b 1
)
start "" ".tools\godot\Godot_v4.7.2-stable_win64.exe" --path "%~dp0."

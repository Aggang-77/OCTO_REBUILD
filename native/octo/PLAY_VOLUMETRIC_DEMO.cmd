@echo off
rem Experimental 3D tetrahedral arm #0 on each octopus; ordinary demo unaffected.
setlocal
set "OCTO_VOLUME_ARM=1"
cd /d "%~dp0"
call "%~dp0PLAY_DEMO.cmd"
endlocal

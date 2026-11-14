param([ValidateSet(1,2,5,10)][int]$Animals=2,[switch]$Benchmark,[string]$Screenshot='', [switch]$Headless)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$server=Join-Path $root 'build/release-final/octo_server.exe'
$asset=Join-Path $root 'game/assets/Octopus_GameReady_v5.glb'
if (-not (Test-Path $server)) { throw "Build the server first: tools/build.ps1 -NoTests" }
if (-not (Test-Path $asset)) { throw "Copy the GameReady GLB to $asset" }
$env:OCTO_SERVER=$server
$env:APPDATA=Join-Path $root 'work/appdata'
$env:LOCALAPPDATA=Join-Path $root 'work/localappdata'
New-Item -ItemType Directory -Force $env:APPDATA,$env:LOCALAPPDATA | Out-Null
$argsList=@('--path', (Join-Path $root 'game'))
if ($Headless) { $argsList+= '--headless' }
$argsList+= @('--', "--animals=$Animals")
if ($Benchmark) { $argsList+= '--benchmark' }
if ($Screenshot) { $argsList+= "--screenshot=$Screenshot" }
$p=Start-Process 'C:\Tools\Godot\godot.exe' -ArgumentList $argsList -WindowStyle Hidden -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Godot exited $($p.ExitCode)" }

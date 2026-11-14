param([ValidateSet(1,2,5,10)][int]$Animals=2,[switch]$Benchmark,[string]$Screenshot='', [switch]$Headless,[ValidateRange(8,64)][int]$Segments=24,[switch]$NoWriggle,[switch]$LegacyProfile)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$server=Join-Path $root 'build/release-final/octo_server.exe'
$asset=Join-Path $root 'game/assets/Octopus_GameReady_v5.glb'
$godot='C:\Tools\Godot\godot.exe'
if (-not (Test-Path $server)) { throw "Build the server first: tools/build.ps1 -NoTests" }
if (-not (Test-Path $asset)) { throw "Copy the GameReady GLB to $asset" }
if (-not (Test-Path $godot)) { throw "Godot executable missing: $godot" }
$env:OCTO_SERVER=$server
$env:APPDATA=Join-Path $root 'work/appdata'
$env:LOCALAPPDATA=Join-Path $root 'work/localappdata'
New-Item -ItemType Directory -Force $env:APPDATA,$env:LOCALAPPDATA | Out-Null
$argsList=@('--path', (Join-Path $root 'game'))
if ($Headless) { $argsList+= '--headless' }
$argsList+= @('--', "--animals=$Animals", "--segments=$Segments")
if ($NoWriggle) { $argsList+= '--no-wriggle' }
if ($LegacyProfile) { $argsList+= '--legacy-profile' }
if ($Benchmark) { $argsList+= '--benchmark' }
if ($Screenshot) { $argsList+= "--screenshot=$Screenshot" }
$windowStyle=if ($Headless) { 'Hidden' } else { 'Normal' }
$p=Start-Process $godot -ArgumentList $argsList -WindowStyle $windowStyle -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Godot exited $($p.ExitCode)" }

param([ValidateSet(1,2,5,10)][int]$Animals=2,[switch]$Benchmark,[string]$Screenshot='', [switch]$Headless,[ValidateRange(8,64)][int]$Segments=24,[switch]$NoWriggle,[switch]$LegacyProfile,[switch]$Procedural,[switch]$NoJelly,[switch]$Jelly,[ValidateRange(0.0,3.0)][double]$JellyStrength=2.2,[ValidateRange(0.8,2.6)][double]$JellyThickness=1.50,[switch]$NoWebbing)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$server=Join-Path $root 'build/release-final/octo_server.exe'
$asset=Join-Path $root 'game/assets/Octopus_GameReady_v5.glb'
$godot='C:\Tools\Godot\godot.exe'
if (-not (Test-Path $server)) { throw "Build the server first: tools/build.ps1 -NoTests" }
if (-not $Procedural -and -not (Test-Path $asset)) { throw "Copy the GameReady GLB to $asset, or launch with -Procedural" }
if ($Procedural -and $NoJelly) { throw "-Procedural requires the jelly renderer; omit -NoJelly" }
if ($Jelly -and $NoJelly) { throw "Choose either -Jelly or -NoJelly" }
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
if ($Procedural) { $argsList+= '--procedural' }
if ($NoJelly) { $argsList+= '--no-jelly' }
if ($Jelly) { $argsList+= '--jelly' }
$argsList+= "--jelly-strength=$JellyStrength"
$argsList+= "--jelly-thickness=$JellyThickness"
if ($NoWebbing) { $argsList+= '--no-webbing' }
if ($Benchmark) { $argsList+= '--benchmark' }
if ($Screenshot) { $argsList+= "--screenshot=$Screenshot" }
$windowStyle=if ($Headless) { 'Hidden' } else { 'Normal' }
$p=Start-Process $godot -ArgumentList $argsList -WindowStyle $windowStyle -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Godot exited $($p.ExitCode)" }

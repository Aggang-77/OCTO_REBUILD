param(
    [ValidateSet(1,2,5,10)][int]$Animals=2,
    [switch]$Benchmark,
    [string]$Screenshot='',
    [switch]$Headless,
    [ValidateRange(8,64)][int]$Segments=16,
    [switch]$NoWriggle,
    [switch]$LegacyProfile,
    [switch]$Procedural,
    [switch]$TestControls
)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$server=Join-Path $root 'build/release-final/octo_server.exe'
$asset=Join-Path $root 'game/assets/Octopus_GameReady_v5.glb'
$godot='C:\Tools\Godot\godot.exe'
if (-not (Test-Path $server)) { throw "Build the C++ server first: tools/build.ps1" }
if (-not (Test-Path $godot)) { throw "Godot executable missing: $godot" }
if (-not $Procedural -and -not (Test-Path $asset)) {
    Write-Host "GameReady model unavailable. Using fast shader-free MultiMesh octopus."
    $Procedural=$true
}
$env:OCTO_SERVER=$server
$env:APPDATA=Join-Path $root 'work/appdata'
$env:LOCALAPPDATA=Join-Path $root 'work/localappdata'
New-Item -ItemType Directory -Force $env:APPDATA,$env:LOCALAPPDATA | Out-Null
$argsList=@('--path',(Join-Path $root 'game'))
if ($Headless) { $argsList+= '--headless' }
$argsList+= @('--',"--animals=$Animals","--segments=$Segments")
if ($NoWriggle) { $argsList+= '--no-wriggle' }
if ($LegacyProfile) { $argsList+= '--legacy-profile' }
if ($Procedural) { $argsList+= '--procedural' }
if ($Benchmark) { $argsList+= '--benchmark' }
if ($TestControls) { $argsList+= '--test-controls' }
if ($Screenshot) { $argsList+= "--screenshot=$Screenshot" }
$windowStyle=if ($Headless) { 'Hidden' } else { 'Normal' }
$p=Start-Process $godot -ArgumentList $argsList -WindowStyle $windowStyle -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Godot exited $($p.ExitCode)" }

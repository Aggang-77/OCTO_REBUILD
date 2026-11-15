param([ValidateSet(1,2,5,10)][int]$Animals=2,[switch]$Benchmark,[string]$Screenshot='', [switch]$Headless)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$server=Join-Path $root 'build/release-final/octo_server.exe'
# A separate verified build allows a new demo while Windows still holds
# the previous executable open. Select only these two known local outputs.
$serverCandidates = @('build/release-final/octo_server.exe', 'build/release-soft-web/octo_server.exe', 'build/release-controls/octo_server.exe') |
    ForEach-Object { Get-Item -LiteralPath (Join-Path $root $_) -ErrorAction SilentlyContinue } |
    Sort-Object LastWriteTimeUtc -Descending
if ($serverCandidates) { $server = @($serverCandidates)[0].FullName }
$asset=Join-Path $root 'game/assets/Octopus_GameReady_v5.glb'
$godot='C:\Tools\Godot\godot.exe'
# A pre-v1 binary can exist at this path and still reject Godot's
# 'step2' operation with bad_operation. Recompile if code is newer,
# then exercise the *real* protocol in a disposable server process.
$buildScript = Join-Path $PSScriptRoot 'build.ps1'
$probeScript = Join-Path $PSScriptRoot 'check-bridge.ps1'
$nativeSources = @(
    'bridge/server.cpp',
    'core/world.cpp',
    'include/octo/world.hpp',
    'CMakeLists.txt'
)
$needsBuild = -not (Test-Path -LiteralPath $server -PathType Leaf)
if (-not $needsBuild) {
    $serverTime = (Get-Item -LiteralPath $server).LastWriteTimeUtc
    foreach ($relativePath in $nativeSources) {
        $sourceFile = Join-Path $root $relativePath
        if ((Get-Item -LiteralPath $sourceFile).LastWriteTimeUtc -gt $serverTime) {
            $needsBuild = $true
            break
        }
    }
}
function Invoke-OCTOBuild {
    Write-Host '[OCTO] Rebuilding native C++ server (controls v1.0)...'
    & $buildScript -NoTests
    $script:server = Join-Path $root 'build/release-final/octo_server.exe'
    if (-not (Test-Path -LiteralPath $server -PathType Leaf)) {
        throw "Build succeeded without creating $server"
    }
}
if ($needsBuild) {
    Invoke-OCTOBuild
}
try {
    & $probeScript -Server $server
} catch {
    if ($needsBuild) {
        throw "Newly built C++ server failed controls v1.0 compatibility check: $_"
    }
    Write-Warning "[OCTO] Stale or incompatible C++ server: $_"
    Invoke-OCTOBuild
    try {
        & $probeScript -Server $server
    } catch {
        throw "C++ server is still incompatible after a rebuild: $_"
    }
}
if (-not (Test-Path $asset)) { throw "Copy the GameReady GLB to $asset" }
if (-not (Test-Path $godot)) { throw "Godot executable missing: $godot" }
$env:OCTO_SERVER=$server
$env:APPDATA=Join-Path $root 'work/appdata'
$env:LOCALAPPDATA=Join-Path $root 'work/localappdata'
New-Item -ItemType Directory -Force $env:APPDATA,$env:LOCALAPPDATA | Out-Null
$argsList=@('--path', (Join-Path $root 'game'))
if ($Headless) { $argsList+= '--headless' }
$argsList+= @('--', "--animals=$Animals")
if ($Benchmark) { $argsList+= '--benchmark' }
if ($Screenshot) { $argsList+= "--screenshot=$Screenshot" }
$windowStyle=if ($Headless) { 'Hidden' } else { 'Normal' }
$p=Start-Process $godot -ArgumentList $argsList -WindowStyle $windowStyle -Wait -PassThru
if ($p.ExitCode -ne 0) { throw "Godot exited $($p.ExitCode)" }

param([string]$Zig = '', [switch]$Tests)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $Zig) { $Zig = Join-Path $projectRoot '.tools/compiler/zig-windows-x86_64-0.13.0/zig.exe' }
if (-not (Test-Path -LiteralPath $Zig)) { throw 'Set -Zig to a Zig 0.13+ executable (https://ziglang.org/download/).' }
Push-Location $projectRoot
try {
    $buildDirectory = Join-Path $projectRoot '.tools/build-octopus'
    New-Item -ItemType Directory -Path $buildDirectory -Force | Out-Null
    $worldObject = Join-Path $buildDirectory 'world.obj'
    & $Zig c++ -std=c++20 -O2 -I native/octo/include -c native/octo/core/world.cpp -o $worldObject
    if ($LASTEXITCODE -ne 0) { throw 'Octopus physics build failed' }
    & $Zig c++ -std=c++20 -O2 -I native/octo/include $worldObject native/octo/bridge/game_server.cpp -o native/octo/octo_game_server.exe
    if ($LASTEXITCODE -ne 0) { throw 'Octopus engine build failed' }
    if ($Tests) {
        foreach ($testName in @('physics_tests','controls_v1_tests','contact_mantle_tests','viscoelastic_tests','volumetric_arm_tests','scene_coupling_tests','integration_tests','static_geometry_tests')) {
            & $Zig c++ -std=c++20 -O2 -I native/octo/include $worldObject "native/octo/tests/$testName.cpp" -o ".tools/$testName.exe"
            if ($LASTEXITCODE -ne 0) { throw "Build failed: $testName" }
            & ".\.tools\$testName.exe"
            if ($LASTEXITCODE -ne 0) { throw "Test failed: $testName" }
        }
    }
} finally { Pop-Location }

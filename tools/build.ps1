param([ValidateSet('Release','Debug')][string]$Configuration='Release', [switch]$Asan, [switch]$NoTests)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'enter-dev.ps1')
$taskRoot = Split-Path $PSScriptRoot -Parent
$suffix = if ($Asan) { '-asan' } else { '' }
$taskBuild = Join-Path $taskRoot ('build/' + $Configuration.ToLowerInvariant() + $suffix)
$asanValue = if ($Asan) { 'ON' } else { 'OFF' }
& cmake -S $taskRoot -B $taskBuild -G Ninja "-DCMAKE_BUILD_TYPE=$Configuration" "-DOCTO_ASAN=$asanValue"
if ($LASTEXITCODE -ne 0) { throw 'CMake configuration failed' }
& cmake --build $taskBuild --parallel 4
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
if (-not $NoTests) {
    & ctest --test-dir $taskBuild --output-on-failure --no-tests=error
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
}

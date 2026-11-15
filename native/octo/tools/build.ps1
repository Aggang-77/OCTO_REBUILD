param(
    [ValidateSet('Release','Debug')][string]$Configuration='Release',
    [switch]$Asan,
    [switch]$NoTests
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'enter-dev.ps1')

$taskRoot = Split-Path $PSScriptRoot -Parent
$suffix = if ($Asan) { '-asan' } else { '' }
$taskBuild = Join-Path $taskRoot ('build/' + $Configuration.ToLowerInvariant() + '-final' + $suffix)
$asanValue = if ($Asan) { 'ON' } else { 'OFF' }

# Old local CMake caches may use a different generator, source directory,
# compiler or Windows SDK. --fresh (CMake >= 3.24) invalidates *only*
# configuration cache/CMakeFiles, without deleting local files or assets.
# Do not bypass the compiler check by setting CMAKE_CXX_COMPILER_WORKS=TRUE.
$cmakeTool = Get-Command cmake.exe -ErrorAction SilentlyContinue
if (-not $cmakeTool) {
    throw 'CMake not found. Install CMake >= 3.25 and restart PowerShell.'
}
$ninjaTool = Get-Command ninja.exe -ErrorAction SilentlyContinue
if (-not $ninjaTool) {
    throw ('Ninja not found. Install Ninja or Visual Studio CMake tools. ' +
           'Expected ninja.exe on PATH or in a Visual Studio CMake installation.')
}
$msvcTool = Get-Command cl.exe -ErrorAction SilentlyContinue
if (-not $msvcTool) {
    throw 'MSVC cl.exe not found after vcvars64.bat. Install Visual Studio Desktop development with C++.'
}
New-Item -ItemType Directory -Force -Path $taskBuild | Out-Null

Write-Host "[OCTO] CMake: $($cmakeTool.Source)"
Write-Host "[OCTO] Ninja: $($ninjaTool.Source)"
Write-Host "[OCTO] MSVC: $($msvcTool.Source)"
Write-Host "[OCTO] Build directory: $taskBuild"
Write-Host '[OCTO] Refreshing CMake cache to avoid old generator/compiler conflicts.'

$configureArgs = @(
    '--fresh',
    '-S', $taskRoot,
    '-B', $taskBuild,
    '-G', 'Ninja',
    "-DCMAKE_BUILD_TYPE=$Configuration",
    "-DOCTO_ASAN=$asanValue",
    '-DCMAKE_CXX_COMPILER=cl.exe',
    "-DCMAKE_TRY_COMPILE_CONFIGURATION=$Configuration"
)
& $cmakeTool.Source @configureArgs
if ($LASTEXITCODE -ne 0) {
    $code = $LASTEXITCODE
    $diagnostic = Join-Path $taskBuild 'CMakeFiles/CMakeConfigureLog.yaml'
    Write-Warning "[OCTO] Configuration failed with exit code $code."
    Write-Warning '[OCTO] The actual CMake compiler/SDK error is printed above.'
    if (Test-Path -LiteralPath $diagnostic) {
        Write-Warning "[OCTO] More details: $diagnostic"
    }
    throw "CMake configuration failed (exit code $code). Please copy the first CMake Error above this message."
}
& $cmakeTool.Source --build $taskBuild --parallel 4
if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed (exit code $LASTEXITCODE). Check compiler errors printed above."
}
if (-not $NoTests) {
    & ctest --test-dir $taskBuild --output-on-failure --no-tests=error
    if ($LASTEXITCODE -ne 0) {
        throw "Tests failed (exit code $LASTEXITCODE). Check CTest details printed above."
    }
}
Write-Host "[OCTO] BUILD_OK configuration=$Configuration path=$taskBuild"

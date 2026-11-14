$ErrorActionPreference = 'Stop'
$vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
$installation = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
if (-not $installation) { throw 'MSVC C++ build tools not found' }
$vendorBatch = Join-Path $installation 'VC\Auxiliary\Build\vcvars64.bat'
$vendorEnvironment = & $env:ComSpec /d /s /c "`"$vendorBatch`" >nul && set"
foreach ($entry in $vendorEnvironment) {
    if ($entry -match '^([^=]+)=(.*)$') { Set-Item -Path "Env:$($Matches[1])" -Value $Matches[2] }
}
$taskRoot = Split-Path $PSScriptRoot -Parent
$taskWork = Join-Path $taskRoot 'work'
$env:TEMP = Join-Path $taskWork 'temp'
$env:TMP = $env:TEMP
$env:APPDATA = Join-Path $taskWork 'appdata'
$env:LOCALAPPDATA = Join-Path $taskWork 'localappdata'
New-Item -ItemType Directory -Force $env:TEMP,$env:APPDATA,$env:LOCALAPPDATA | Out-Null
$env:VSLANG = '1033'
$env:PATH = "C:\Program Files\CMake\bin;C:\ninja;$env:PATH"


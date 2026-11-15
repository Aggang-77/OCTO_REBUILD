param([switch]$LocateOnly)
$ErrorActionPreference = 'Stop'
$projectRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
$exeName = 'Godot_v4.7.2-stable_win64.exe'
$candidates = New-Object 'System.Collections.Generic.List[string]'
if ($env:GODOT_EXE) { $candidates.Add($env:GODOT_EXE.Trim('"')) }
$candidates.Add((Join-Path $projectRoot ".tools/godot/$exeName"))
foreach ($name in @('godot.exe','godot4.exe',$exeName)) {
    $command = Get-Command $name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command) { $candidates.Add($command.Source) }
}
foreach ($folder in @([Environment]::GetFolderPath('Desktop'), 'C:/Tools/Godot', 'C:/Program Files/Godot')) {
    if ($folder) { $candidates.Add((Join-Path $folder $exeName)) }
}
try {
    Get-CimInstance Win32_Process -Filter "Name = '$exeName'" -ErrorAction Stop | ForEach-Object {
        if ($_.ExecutablePath) { $candidates.Add($_.ExecutablePath) }
    }
} catch { }
$parent = Split-Path $projectRoot -Parent
foreach ($folder in @($parent, (Split-Path $parent -Parent))) {
    if ($folder) { $candidates.Add((Join-Path $folder "octopus-simulator/.tools/godot/$exeName")) }
}
$godot = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
if (-not $godot) {
    Write-Host 'Godot 4.7.2 was not found. Install Godot or set GODOT_EXE to its executable.' -ForegroundColor Red
    Write-Host 'https://godotengine.org/download/windows/'
    exit 1
}
if (-not (Test-Path -LiteralPath (Join-Path $projectRoot 'native/octo/octo_game_server.exe'))) {
    Write-Host 'The bundled octopus engine is missing. Run tools/build_octopus.ps1.' -ForegroundColor Red
    exit 1
}
if ($LocateOnly) { Write-Output $godot; exit 0 }

# Updated copies share one launcher lock, avoiding duplicate game windows.
$mutex = New-Object Threading.Mutex($false, 'Local\OctopusSimulatorGame')
$owned = $false
try {
    try { $owned = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $owned = $true }
    if (-not $owned) { Write-Host 'This game is already starting or running. Use Alt+Tab to select it.'; exit 0 }
    $running = Get-CimInstance Win32_Process -Filter "Name LIKE 'Godot%'" -ErrorAction SilentlyContinue | Where-Object {
        $line = $_.CommandLine
        $line -and ($line.Contains($projectRoot) -or $line -match 'octopus-simulator|OCTO_REBUILD') -and $line -match '(?:^|\s)--path(?:\s|$)' -and
        $line -notmatch '(?:^|\s)(?:--editor|-e|--headless|--script)(?:\s|$)'
    } | Select-Object -First 1
    if ($running) { Write-Host 'This game is already running. Use Alt+Tab to select it.'; exit 0 }
    Write-Host "Starting game from: $projectRoot"
    Write-Host 'The first map load can take 10-20 seconds. Please wait without opening another copy.'
    $game = Start-Process -FilePath $godot -ArgumentList @('--path', ('"' + $projectRoot + '"')) -WorkingDirectory $projectRoot -WindowStyle Normal -PassThru
    $game.WaitForExit()
    exit $game.ExitCode
} finally {
    if ($owned) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}

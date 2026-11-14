param(
    [Parameter(Mandatory=$true)][string]$Server,
    [ValidateRange(1000,30000)][int]$TimeoutMs = 10000
)
$ErrorActionPreference = 'Stop'

# Run a disposable copy of the native server and exercise the exact
# controls-v1 operation the Godot client will send. Existence alone is
# insufficient: older octo_server.exe builds accept reset but reject step2.
if (-not (Test-Path -LiteralPath $Server -PathType Leaf)) {
    throw "C++ server executable is missing: $Server"
}
$exe = (Resolve-Path -LiteralPath $Server).Path
$info = [System.Diagnostics.ProcessStartInfo]::new()
$info.FileName = $exe
$info.UseShellExecute = $false
$info.RedirectStandardInput = $true
$info.RedirectStandardOutput = $true
$info.CreateNoWindow = $true
$process = [System.Diagnostics.Process]::new()
$process.StartInfo = $info

function Invoke-BridgeProbe {
    param([int]$RequestId,[string]$Command)
    $process.StandardInput.WriteLine("1 $RequestId $Command")
    $process.StandardInput.Flush()
    $read = $process.StandardOutput.ReadLineAsync()
    if (-not $read.Wait($TimeoutMs)) {
        throw "C++ bridge timed out on '$Command' after $TimeoutMs ms"
    }
    $line = $read.Result
    if ([string]::IsNullOrEmpty($line)) {
        throw "C++ bridge exited without replying to '$Command'"
    }
    try {
        $reply = $line | ConvertFrom-Json -ErrorAction Stop
    } catch {
        throw "C++ bridge returned invalid JSON for '$Command': $line"
    }
    if ($reply.version -ne 1 -or $reply.id -ne $RequestId) {
        throw "C++ bridge returned the wrong protocol version or request ID"
    }
    if (-not $reply.ok) {
        throw "C++ bridge rejected '$Command' with error '$($reply.error)'"
    }
    return $reply
}

try {
    if (-not $process.Start()) {
        throw "Unable to start C++ server: $exe"
    }
    $reset = Invoke-BridgeProbe -RequestId 1 -Command 'reset 1 2.2 1'
    if ($reset.snapshot.tick -ne 0) {
        throw "C++ server reset response is invalid"
    }
    $arms = (0..7 | ForEach-Object { "0 $_ 1 0 1.28 0 0.15 0 -1" }) -join ' '
    $command = "step2 8 $arms 0 0 0 0 0 0 30 20 0"
    $advanced = Invoke-BridgeProbe -RequestId 2 -Command $command
    if ($advanced.snapshot.tick -ne 1) {
        throw "C++ bridge did not advance a controls-v1 simulation step"
    }
    $first = $advanced.snapshot.animals[0].arms[0]
    if ($null -eq $first -or $null -eq $first.attached) {
        throw "C++ server is missing controls-v1 sucker fields"
    }
    $quit = Invoke-BridgeProbe -RequestId 3 -Command 'quit'
    Write-Host "BRIDGE_V1_PREFLIGHT_PASS step2=true suction=true server=$exe"
} finally {
    if ($process) {
        if (-not $process.HasExited) {
            try { $process.Kill() } catch {}
        }
        $process.Dispose()
    }
}

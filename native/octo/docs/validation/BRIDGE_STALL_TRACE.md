# Godot pipe stall investigation — 2026-11-15

The dynamic prop guard remained numerically stable in CTest and native
benchmarks, but two of the first four ten-animal Godot 600-tick runs exited 2
after the 15-second response watchdog. Later four repeated runs all exited 0
at 57.544, 58.772, 58.168 and 58.451 simulation ticks/s. A further trial
with 200 microsecond pipe polling instead of 1 ms yielded one timeout and one
success (57.383 ticks/s); it did not improve throughput and was reverted.

The extra timeout message identified one concrete stalled state: last displayed
simulation tick 433, request ID 435 allocated, response ID 434 last
validated, `pending=false`. That flag can be overwritten by the main thread
while the reader schedules the next request, so its value alone does not
prove the request was not in flight or that bytes were written. The timeout now also reports reader-thread
and child-process liveness. Another timeout in the restored 1 ms polling
configuration recorded tick 276, request 278, response 277, with both the
reader thread and child process alive. The pending flag now reflects whether
the latest request ID exceeds the latest validated response ID, under the
inbox mutex; it was true for that timeout. The reader now records its current
read/write phase and last available-byte count to distinguish the next
failure. Six subsequent instrumented 600-tick runs passed at 56.833–58.547
ticks/s, so the phase of a failed run has not yet been captured.

`tools/bridge_stress.py` sends the same fixed 80-arm active command to the
native server as the Godot benchmark and validates 600 versioned replies.
Three independent runs passed in 6.170, 6.189 and 6.209 seconds (about
97 ticks/s). This narrows the intermittent stall to the process/transport/UI
combination for these runs, but does not rule out a server stall under a
different input sequence or environment condition.

A trial using blocking `FileAccess.get_line()` in Godot failed even the
two-animal initial reset after 15 seconds; that trial was reverted. The
restored polling reader passed a two-animal 60-tick Godot smoke with exit 0.
Do not characterize the blocking API as a fix. Next isolate whether the
native child remains alive and whether the reader thread is alive when a
timeout recurs; then inspect the request write and response read boundary.
Maintain independent performance and stability gates: the successful dense
ten-animal runs remain below sustained 60 simulation ticks/s.

Reproduce the direct native stream:

```powershell
C:\Anaconda\python.exe .\tools\bridge_stress.py .\build\release-final\octo_server.exe 600
```

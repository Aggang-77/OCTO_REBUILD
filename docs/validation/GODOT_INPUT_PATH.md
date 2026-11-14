# Godot input path, 2026-11-15

The `game.input` CTest launches the original GameReady model in headless Godot
with two animals and the real C++ server for 120 physics ticks. Godot injects
Tab, Q, a left click on animal 2 and mouse motion through `Input.parse_input_event`.
The production `_unhandled_input` handler selects and picks; `step_command`
serializes all eight arms for each animal and the bounded drag target. The
server replies with C++ world snapshots.

Observed Release run: selected index 1, arm command observed, animal drag
command observed, arm relative-tip divergence from its pre-input baseline
0.16380 m, and animal 2 horizontal center travel during drag 0.77382 m.
`SMOKE_OK tick=120`; `ctest` 4/4 passed. The UI previously intercepted a click
at screen coordinate (43.5, 34.9); all display-only controls now ignore mouse
events. A failing input check exits Godot with status 2.

This checks Godot event dispatch, command construction, server exchange and
resulting motion together. The center movement is not a precise isolated drag
force measurement: gravity and other contacts remain enabled. A synthetic
headless input sequence does not replace a human playability review or prove
every arm key/attachment mode. The test is registered when Godot and the GLB
are present at CMake configure time.

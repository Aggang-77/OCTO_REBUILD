# OCTO_REBUILD import

Imported from the local `GitHub/OCTO_REBUILD` checkout at
`7a93c0e886cc7625f44c778e98c5abaee31ff129` on 2026-11-15.
The original checkout is preserved. `core`, `include`, `bridge/server.cpp` and
the original tests retain their source structure. The Godot skin/input/reader
client is retained in `scripts/octopus/rebuild_demo.gd` with its model path and
pipe write mode adapted. `octopus_controller.gd` owns the merged request worker.
The original local GameReady v5 asset is in `assets/octopus`.

The merged client adds a `game_server.cpp` executable, terrain height samples,
per-site scene forces, and contact planes queried from the real Godot shapes.
The octopus stays in its C++ XPBD solver at 1/60 s. Hunters and map props retain
their existing Godot/Jolt physics. Their spring reactions are sent to native
sites, and native scene-contact impulses are applied back to Godot bodies once.
This is explicit sample-and-hold coupling between two solvers, not a migration
of the character or map props into the original single C++ world. Large/fast
contacts can need tuning; the contact bridge is discrete, not general CCD.
Terrain uses a 65 by 65 bilinear heightfield plus nearby actual scene contacts.

Controls preserve the original bounded muscle targets and force drag. A sword
can disable an arm's threat, grabbing and control until round reset. The visible
GameReady mesh is retained; this does not implement mesh amputation.

Build locally with `tools/build_octopus.ps1 -Tests`, or build the native target
`octo_game_server` with CMake and a C++20 compiler. The current Windows binary
is included beside this file so launching the merged game needs no compiler.

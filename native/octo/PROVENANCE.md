# OCTO_REBUILD import

## Local main merge (2026-11-15)

The integrated project now includes `songhh06/OCTO_REBUILD` main at
`5199960`, merged beneath `native/octo` on `local/merge-octo-main`.
Git records the previously imported `7a93c0e` baseline and the newer upstream
history; the root Godot game, characters, map and hidden fight mode are retained.

The latest stable motor/suction multipliers, progressive uncoiling,
surface-following, upright recovery, 19-node mantle cage/shell, viscous tissue
and bounded creep are used by the integrated game. Input now matches upstream:
extension 1.48/0.58 and stiffness 0.02. The render client also retains upstream's
texture-preserving wet PBR finish and physical mantle-root skin deformation.

Terrain-seeking, following and suction anchors use the actual heightfield, and
all 19 body sites support the existing scene-force/contact adapter. The separate
tetrahedral-arm prototype remains an explicit native opt-in as it is upstream;
the normal integrated launcher uses the stable default physics configuration.

The two-solver coupling limitations described below still apply.

Validation on Windows with Zig 0.13.0 and Godot 4.7.2:

- Native physics, controls-v1, viscoelastic, volumetric-arm, scene-coupling and
  integration suites: PASS. The coupling fixture verifies real suction on a
  raised heightfield and reactions applied to all 19 body sites.
- Integrated input/renderer/objective/reset suite: 40/40 PASS.
- Real-contact capture, hidden-fight interruption and ten-second victory:
  9/9 PASS, including a rendered victory screenshot.
- Hidden-fight entry, keyboard combat, suspension and return: 23/23 PASS.

These results verify the tested fixtures; they are not a full performance or
biological-fidelity acceptance claim.

## Original import

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

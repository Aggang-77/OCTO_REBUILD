# OCTO_REBUILD — fast C++ octopus simulator

Godot 4.6.2 render client + C++ fixed-step XPBD physical world.
The original OCTO repository remains an untouched historical reference.

## Play on Windows

Requires MSVC/CMake and Godot at `C:\Tools\Godot\godot.exe`.
The original GameReady model, when available, belongs at
`game/assets/Octopus_GameReady_v5.glb` (not committed to Git).

```powershell
git switch feat/soft-wriggling-arms
git pull --ff-only
.\tools\build.ps1
.\PLAY_DEMO.cmd
```

If the original GLB is missing, the launcher automatically uses an
inexpensive **MultiMesh** octopus approximation. To force this fast
fallback even with a GLB:

```powershell
.\tools\run-demo.ps1 -Animals 2 -Procedural -Segments 16
```

The former GPU jelly shader and 8 inter-arm cosmetic membrane
generators have been **removed**. Only ordinary Godot materials remain.
The demo defaults to 16 rod segments per arm rather than 24 to lower
physics and skin costs. `-Segments 24` is still supported for comparison.

## Game controls v1.0

| Arm | Extend/retract | Stroke back/forward |
|---|---|---|
| Left front | **F** | **D** |
| Right front | **J** | **K** |
| Left side-front | **S** | **A** |
| Right side-front | **L** | **;** |
| Left side-rear | **R** | **E** |
| Right side-rear | **U** | **I** |
| Left rear | **W** | **Q** |
| Right rear | **O** | **P** |

**Hold extend:** stretch the arm; release to retract/curl.
**Hold stroke:** sweep the arm toward the back; release to
return toward the front. Both controls can be held simultaneously.
**Space:** release all sucker attachments and suppress re-grip
while held; a cooldown applies on release.

`Tab` switches selected octopus, `F5` resets, left mouse drag applies
bounded physical force to the octopus/box, right drag rotates the camera.
These developer/debug controls coexist with v1 keyboard controls.

Read [the exact mapping, physics thresholds and fidelity limits](docs/design/CONTROL_V1.md).

## Native tests / real-time limits

```powershell
.\tools\build.ps1
.\build\release-final\octo_benchmark.exe 2 600
```

GitHub Actions builds Linux C++ and Windows MSVC, runs
CTest physics/bridge/integration checks, and runs an actual Godot
OpenGL/software-render screenshot smoke of two procedural animals.
The control smoke synthesizes simultaneous extend/stroke input,
release-to-return, and a Space override, while native tests check
the suction/cooldown path.

The old membrane screenshots and measurements in
`docs/validation/JELLY_MEMBRANE.md` and
`docs/validation/INTERBRACHIAL_WEB.md` are historical and **no
longer describe active runtime code**.

Real original-model playability and Windows hardware 60 FPS must
be validated on a machine with the untracked GameReady GLB.
C++ suction uses discretized rod sites, not high-fidelity anatomical
suckers or deformable skin contacts.

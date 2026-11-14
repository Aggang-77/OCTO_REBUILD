# Extreme GPU jelly envelope — octopus demo

## Goal and architecture
The C++ XPBD arm simulation remains authoritative for all forces,
attachment, gravity, collision and volume-proxy section radii. Godot
reconstructs a **cosmetic** surface from each of eight physical arm
centerlines, Catmull–Rom interpolates the C++ nodes and radius ellipse,
and draws a 12-sided skinned-look fleshy envelope with 2 subdivisions
per physical segment. The new `res://shaders/jelly_octopus.gdshader`
displaces the vertex surface by several traveling spatio-temporal
normal waves and a larger recoil following actual rod-tip motion
or a mouse drag. The GPU displacement is bounded by each section's
physical radius (in `UV2.x`) to avoid inverted/paper-thin tips.

In standalone `--procedural` mode no GameReady GLB is needed: there
are eight C++ driven arms and a softly pulsing procedural sphere mantle
for each animal. When the original GLB exists, its head/eyes and skin
are preserved and wide jelly sleeves surround its arms. The physical
material/radius is shared with the solver only at the coarse rod level,
not vertex-by-vertex.

## Run
On Windows after installing Godot in `C:\Tools\Godot\godot.exe` and
running `./tools/build.ps1`:

```powershell
.\PLAY_DEMO.cmd
.\tools\run-demo.ps1 -Animals 2 -Procedural -JellyStrength 2.2
.\tools\run-demo.ps1 -Animals 2 -JellyStrength 3.0
.\tools\run-demo.ps1 -Animals 2 -NoJelly
```

PageUp/PageDown: jelly intensity (0..3); F6: show/hide jelly.
`--procedural` forces the renderer on; `--jelly` forces it on for
more than two animals (otherwise it is off for performance).

## Automated evidence
GitHub workflow `jelly-render` uses Godot 4.6.2, OpenGL Compatibility,
Mesa llvmpipe software GL and Xvfb. It starts C++ server, renders 90
simulation ticks with two octopuses and props, checks a real
1280x720 screenshot, shader-backed meshes, no GDScript/shader errors,
and archives the PNG and log in a `jelly-preview-linux` CI artifact.

First passing actual GPU pipeline: 
https://github.com/songhh06/OCTO_REBUILD/actions/runs/43628842241
- `JELLY_CHECK animals=2 arms=8 vertices_per_arm=637 strength=2.20`
- `SCREENSHOT ... error=0`, `JELLY_RENDER_PASS ... screenshot=1280x720`
- Native and bridge tests still run separately on Windows and Linux.

This uses **software rendering**, so simulation ticks/s is NOT
comparable with user GPUs. The first preview rendered 89 fixed ticks
in ~2.52 seconds (~35.35 ticks/s); GUI `skin_ms` was ~8.50ms per
snapshot and CPU vertex generation is a performance cost. No
fully saturated 10-animal 60 FPS claim is made for this cosmetic layer.

## Limitations — do not confuse effects with tissue mechanics
- GPU waves deform **appearance only**, with no vertex collision response:
  the visible shell may overlap a prop or another animal and is
  never involved in the C++ contact solver.
- Arm radial profile is an ellipse, not a volumetric continuum tissue
  grid or true mantle pressure model; no real suckers are generated in
  the procedural fallback.
- The GameReady GLB is not tracked in Git and was not available on CI;
  the live GLB + jelly overlay (including sucker clipping) must still
  be checked manually on a computer that has the original asset.
- This wide envelope and the existing broader collision sections can
  increase close-contact workload; large dense scenes default to no
  jelly material for performance.

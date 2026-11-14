# OCTO rebuild

Independent 3D octopus simulator prototype. The original repository is preserved at `../OCTO`; this repository does not import its physics solver. It reuses the user-provided GameReady model as a local render asset. Read `docs/validation/INITIAL_RESULTS.md` and `docs/progress/STATUS.md` before extending it.

On Windows with MSVC, CMake, Ninja and Godot 4.6.2:

Double-click `PLAY_DEMO.cmd` to open the interactive two-octopus scene. If the
native server is not built yet, run `./tools/build.ps1` once in PowerShell.
Click in the Godot window to focus it. Press Tab to switch octopuses, hold
Q/W/E/R/A/S/D/F to move individual arms, and left-click and drag an octopus
or a box to apply a bounded force. Hold Ctrl with an arm key to attach its tip;
Z/X with an arm key twists it. Right-drag orbits the camera; F5 resets.
Closing the Godot window ends the session and its native C++ server.

```powershell
./tools/build.ps1
C:\Tools\Godot\godot.exe --headless --editor --import --path game
./tools/run-demo.ps1 -Animals 2 # New organic rounded profile and automatic muscle waves
./tools/run-demo.ps1 -Animals 2 -Segments 24 -LegacyProfile # Old narrow cone shape
./tools/run-demo.ps1 -Animals 2 -Segments 24 -NoWriggle # Organic silhouette, no automatic motion
./tools/run-demo.ps1 -Animals 2 -Segments 16 # Lower physics cost
./build/release-final/octo_benchmark.exe 10 600 dense
```

The two-animal live scene uses Q W E R A S D F for eight independent arm activation inputs, Tab for animal selection, Ctrl for attachment and left-drag for capped force picking. The physics remains an XPBD approximation rather than a full Cosserat rod. The default rod resolution is now 24 segments (25 simulated nodes) per arm, matched to the GameReady model's 24 bones. The two-animal demo enables slow, traveling 3D idle muscle waves in the **C++ solver**; launch Godot with `--no-wriggle` to disable them. Manual muscle activation suppresses the idle wave for that arm. The bending compliance is softer, while arm mass is kept approximately resolution-independent. In the organic default the arm stays broad through its middle and narrows near its tip; a traveling longitudinal muscle wave redistributes segment rest lengths while the radial ellipse adjusts to preserve local section volume. The GameReady mesh is retargeted with the corresponding C++ section radii, not the original straight taper. `-LegacyProfile` in `run-demo.ps1` restores the linear-cone rest shape for A/B checks. This is still a rod/ellipse proxy, not a full deformable volume mesh. Use `--segments=16` to reduce the demo's CPU load on slower hardware (or `--segments=32` to experiment with finer movement); the 24-segment setting remains the default. Performance trade-off: with the new **organic-profile** radius and 24-segment physics, the hosted Linux 10-animal dense-active test measured mean/p95 **27.51/28.28 ms per native tick**, which **fails the 16.67 ms 60 Hz budget even before rendering**. Two-animal spread-active native mean/p95 was 2.73/2.78 ms. These hosted timings are not interchangeable with the earlier Windows baseline; the broad physical contact surfaces increase collision cost. The earlier async-bridge 60 Hz measurements used the old narrower arms and do not validate the new shape. See `docs/validation/ORGANIC_HYDROSTAT.md` and `docs/validation/ASYNC_10_PERFORMANCE.md`. Full native/Godot original-asset visual verification remains pending.

## Extreme jelly membrane demo (Godot 4.6.2)

The latest `PLAY_DEMO.cmd` opens the **two-octopus jelly demo**. If the untracked
`game/assets/Octopus_GameReady_v5.glb` is missing it automatically starts a
complete **procedural jelly preview** instead of failing.

```powershell
.\tools\build.ps1
.\tools\run-demo.ps1 -Animals 2 -Procedural -JellyStrength 2.2
.\tools\run-demo.ps1 -Animals 2 -JellyStrength 3.0       # with original GLB
.\tools\run-demo.ps1 -Animals 2 -NoJelly                 # physical arms only
.\tools\run-demo.ps1 -Animals 2 -Procedural -Benchmark    # unattended smoke
```

**PageUp/PageDown** change GPU jelly wobble intensity (0–3); **F6** toggles the
membrane. The organic rod sections are rebuilt into smooth rounded tube meshes
(12 radial sides, 2 interpolated rings per physical segment) and an OpenGL
spatial shader adds three traveling ripples and a motion-triggered recoil.
The skinned original GameReady head/eyes are preserved when that asset exists;
the procedural-only preview supplies its own undulating sphere mantle.

This is a **cosmetic skin layer**, not volumetric FEM/MPM or precise
surface-based collision. The simulated C++ particle rods and forces are
unchanged by the shader. In scenes with more than two octopuses, jelly layers
are disabled by default to protect throughput; pass `-Jelly` to force them
on. See `docs/validation/JELLY_MEMBRANE.md` for GPU screenshot proof,
profiling, and known visual/physical limitations.

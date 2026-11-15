# Arm surface and mantle chamber checkpoint (2026-11-15)

The grounded gameplay profile now has 12 additional XPBD mantle chamber
tetrahedra joining its two six-particle outer rings to the central cage.
Each cell has a compliant signed-volume constraint. The shell and arm junction
remain separate dynamic masses, so an arm pull can squeeze one side and move
the mantle while the volume solver reacts through the shared C++ world.

For grounded gameplay, each arm segment midpoint also contacts the face of
the eight-particle dynamic prop proxy using the current prop axes and extents.
The response is distributed over both arm endpoints and all eight prop masses.
Floor projection uses the conservative GameReady envelope for mantle shell
particles as well as centerline arm nodes, including a final post-solver pass.
This addresses gaps between sparse arm particles and box corners. It is an
approximation to a capsule versus deformable box: midpoint sampling can still
miss fast or unusual contacts, and the prop's rendered orientation is only an
approximate match to the eight-particle cage.

The original GameReady material shader now interpolates twelve native shell
offsets around torso-root-weighted vertices; its existing root-bone scale
continues to represent gross deformation. Vertex offsets are limited to
0.12 model units. Imported geometry and bone weights remain unchanged. The
skin-to-contact-surface distance has not been measured in moving poses.

Evidence on the Windows Release build:

- `./tools/build.ps1`: CTest 8/8 PASS. An old input test expected the prior
  arm extension command (1.28); updated it to the current 1.48 command.
- `physics.contact_mantle`, 180 ticks with a pulled arm and three props:
  724 arm-to-prop face corrections, prop motion 0.398 m compared with passive
  fall, shell motion 0.560 m compared with passive fall, maximum local mantle
  cell volume error 0.0181. The arm centerline and mantle shell floor envelopes
  stayed at or above their configured clearance. This is a strong-force stress
  fixture, not a realistic idle deformation calibration.
- Two-animal GameReady GPU scene: 240 ticks, exit 0, 60.10 simulated ticks/s,
  frame interval p95 8.33 ms, screenshot `contact_mantle_skin.png`.
- Ten-animal `grounded_dense` native active run: 600 measured ticks after
  120 warmup, mean/p95 physics 14.17/14.65 ms, no nonfinite values. The older
  benchmark's `dense` option is *legacy rest*, so use `grounded_dense` for this
  feature. A ten-animal Godot FPS gate remains unmeasured here.
- Two-animal `grounded_dense` native active soak: 10,000 measured ticks,
  p95 2.47 ms, zero nonfinite. This does not include GPU skin rendering.

Remaining: continuous arm-surface CCD, direct moving GLB skin clearance
measurement, higher-resolution mantle pressure/volume model, all-arm material
volume, realistic resting silhouette and a player visual review. The current
screen still shows a coarse head and spokes rather than fully organic tissue.

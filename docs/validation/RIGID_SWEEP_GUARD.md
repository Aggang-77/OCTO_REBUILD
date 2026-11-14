# Dynamic prop sweep guard — 2026-11-15

The C++ world now checks each pair of dynamic prop center paths in addition
to its existing particle-sphere sweep. A conservative enclosing sphere radius
`0.16 sqrt(3)` m covers the nominal 0.16 m half-extent cube at rest. On a
crossing or an end-center overlap, equal-and-opposite translation of all eight
corner particles per prop restores the center separation. This runs after
prediction and after the XPBD iteration loop. Reconstructed particle
velocities carry the reaction into the next substep; no Godot physics body
owns the props.

## Evidence

| Check | Result |
| --- | --- |
| MSVC Release `tools/build.ps1`, CTest | PASS, 3/3 |
| 200 N s two-prop impact, no external forces | PASS, order and center separation retained; x momentum 200 kg m/s |
| 400 N s two-prop impact, no external forces | PASS, order retained, center gap about 0.5543 m, x momentum 400 kg m/s |
| 400 N s parallel near miss | PASS, zero swept contacts, z momentum 400 kg m/s |
| Two dense animals, 10,000 measured ticks | PASS, zero nonfinite, mean/p95 0.911/1.060 ms |
| Ten dense active animals, 600 measured ticks | PASS numerically, zero nonfinite, native mean/p95 6.709/7.600 ms |
| Godot 10 dense active animals, 600 ticks | Two exits 0 at 58.611 and 58.544 simulation ticks/s, p95 visible frame interval 8.333 ms; [screenshot](rigid_guard_dense_10.png) inspected |
| Godot 10 dense active animals, 600 ticks | Two earlier exits 2 from the 15 s native-response watchdog; exact stalled tick not recorded |

The 60 ticks/s goal remains unmet in the successful 600-tick runs, and the
two watchdog failures prevent claiming runtime reliability. The Godot failure
message now includes the last observed tick and request/response IDs for the
next reproduction. Two-animal and ten-animal passive 60-tick runs passed after
the failures, as did a ten-animal active 60-tick run.

This guard is a conservative proxy, not exact oriented box CCD. It assumes
nominal corner geometry and translational center paths; it does not resolve
angular motion, deformed prop geometry, whole-arm/torso swept surfaces, or
time-of-impact friction. The high-speed fixture establishes center ordering,
separation, and total linear momentum for those selected straight-line cases.
It does not establish worst-case anatomical contact fidelity or all-speed
stability. Candidate follow-up: exact shape contacts and a native-process
bridge trace for the intermittent watchdog failure, then reduce dense solver
and skin costs with independent 10-animal performance runs.

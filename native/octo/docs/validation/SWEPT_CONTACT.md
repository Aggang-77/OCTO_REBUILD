# Swept sphere contact checkpoint — 2026-11-15

## Change

The shared C++ world now expands its particle broadphase over each substep's
old and predicted positions. If two particle spheres cross during the substep
but end apart, a relative linear sphere sweep computes first contact and the
XPBD position solver projects the endpoints back to the contact side. Contact
bounds are calculated once per solver pass and reuse allocated buffers. A
`swept_contacts` diagnostic counts these constraint applications. An impulse
API for dynamic props provides a reproducible high-speed fixture.

This is a particle-sphere approximation of the GameReady surface and prop
corners. It is not capsule, box, triangle, or angular shape CCD. The sweep
linearizes the center trajectories over one 1/240 s substep; constraint
projections can change trajectories within the pass. Floor contact remains a
plane clamp. Contact count is a constraint application count, not unique pairs.

## Verification

| Check | Result |
| --- | --- |
| `tools/build.ps1` MSVC Release build and CTest | PASS, 3/3 |
| Analytic sweep, crossing/near miss/separating | PASS; first hit t=0.4 |
| Two dynamic props, 200 N s center impulse, no external force | PASS; 44 swept applications, order retained, total x momentum 200 kg m/s within 1e-5 |
| Two dynamic props, 400 N s center impulse | FAIL; body order exchanges despite detected swept contacts. Extreme speed response remains incomplete. |
| Two animals, dense active, 10,000 measured ticks | PASS; 0 nonfinite, mean/p95 1.240/1.654 ms |
| Ten animals, dense active, 600 measured ticks after 120 warmup | PASS numerically; native mean/p95 6.587/7.024 ms, collision mean 4.158 ms, max penetration 0.01509 m, max tetra volume error 0.00828, 0 nonfinite |
| Godot 4.6.2, RTX 4060, ten dense active animals, 600 ticks | PASS execution and screenshot; 56.081 simulation ticks/s, p95 visible frame interval 13.333 ms, solver mean 7.106 ms, skin mean 7.819 ms |

The Godot test exited 0 and saved [the scene](ccd_dense_10.png). The same
change initially yielded ~53 ticks/s before broadphase bounds caching; the
final run still misses the sustained 60 ticks/s target. These measurements
are scenario-specific and cannot establish worst-case performance or tissue
collision accuracy. Native and Godot timings were run independently for the
final measurements.

## Next work

Resolve extreme-speed crossing with time-of-impact velocity/contact handling
and whole-body shape contact, then test nonpenetration and momentum under
several speeds and glancing impacts. Profile the dense scene's collision and
skin costs, preserve 60 ticks/s with headroom, and proceed to deforming torso
surface and full coupled rod orientations. Keep 200 N s regression as a
minimum check, not a proof of general CCD correctness.

# Soft arms and physical traveling-wave motion — 2026-11-15

## Change

- Default rod resolution increased from 16 to 24 segments (25 nodes) per arm. The GameReady model has 24 arm bones; Godot already samples the solver centerline at 24 positions.
- Mass per arm node and section rotational inertia scale by 16/segments so an increase in resolution does not increase total modeled arm mass by 50% (small endpoint discrepancy remains).
- Relaxed bend/shear/director compliances with a resolution-dependent centerline bend compliance. Tuning is artistic/engineering, not measured cephalopod material data.
- The solver precomputes a gently oscillating 3D local curvature *per segment and per substep*. The phase decreases along the arm (root to tip), producing a traveling wave. The amplitude rises toward the tip. The phase differs by arm and animal.
- The wave feeds the XPBD curvature and director constraints and thus alters authoritative C++ particle positions, contacts and reactions. This is **not** a Godot-only skeletal animation. Full tissue, transverse arm cages and anatomical contact are still absent.
- Manual activation fades out idle actuation on that arm without teleporting its particles. `WorldConfig::idle_wriggle` is 0 by default to keep controlled physical fixtures passive; Godot demo sends 1.0 through optional `reset ANIMALS SPACING IDLE` request.
- Use `--no-wriggle` on the Godot command line for A/B comparison; `--segments=16` for lower CPU cost; `--segments=32` to experiment with higher resolution. The earlier two-argument reset request still works. The optional reset grammar is `reset ANIMALS [SPACING [IDLE [SEGMENTS]]]`.

## Validation plan and limitations

- New native physics regression compares zero-gravity isolated idle-wave and passive worlds, checks 24-segment snapshot sizes and observes time-varying node displacement.
- Bridge protocol regression checks the optional reset parameters, node/roll/radius array sizes, invalid strength rejection, and a 16-segment compatibility reset. Optional arguments are now parsed token-by-token to avoid EOF side effects from `peek()`.
- GitHub Actions workflow on commit `3026df96f587395b5d6e23f824d6ad0ed2fcfa08` completed successfully (Linux Release build, native CTest, two-animal benchmark smoke). Subsequent changes and Windows/Godot rendering still require separate checks. Expected computational cost increases with node/contact count; measure before asserting 60 Hz.

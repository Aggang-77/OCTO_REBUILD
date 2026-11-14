# Current status — 2026-11-15 (Asia/Seoul)

G0 baseline PARTIAL: old source inspected read-only; original dirty tree retained.
New independent repo OCTO_REBUILD, base cf42649, separate Sol/Terra worktrees.
No code is copied from the old solver. Original GameReady art will be reused locally.

Implementation underway, no phase declared complete. Sol owns XPBD world,
Terra owns bridge/render/input, Astra owns API/build/integration/performance.
2026-11-15 Sol takeover: initial Sol physics and Terra bridge/Godot work integrated into this repository. Astra stopped at user request; no agents continue working. Build: PASS (MSVC Release via tools/build.ps1). CTest: 2/2 PASS; independent 2-animal 10,000 tick soak PASS. Godot 4.6.2 original GameReady asset loaded with 193 bones and 2/10 animals advanced 60 ticks; visual screenshots captured. GPU scene appears but root/skin physical alignment is unmeasured. Native 10-animal active spread physics mean/p95 4.29/5.10 ms, dense 5.50/5.93 ms on Ryzen 5 5600X. Godot RPC observed ~55.8 ms (2 animals) and ~264.8 ms (10); 60 FPS FAIL. See docs/validation/INITIAL_RESULTS.md and evidence.
Targets: 1-animal real native/Godot vertical slice, then 2 shared-world animals,
then measured 1/2/5/10 load. Full 10-animal 60 FPS and physical feature completeness
are separate, unproven gates. First prototype is not full Cosserat or anatomical tissue.

Original failure lessons: global nonlinear solve had high active-input latency;
normal selection and endpoint contact caused regressions; body/skin mapping hid
physical gaps. New benchmarks include active inputs, reports expose contact/skin
limitations, and deterministic scenarios replace incompatible old binary checkpoints.

2026-11-15 follow-up: main-thread pipe polling caused multi-frame response delay.
Independent reader thread, compact render-only JSON and cached skeleton lookup
reduce 10-animal last-response RPC from ~265 ms to ~19 ms. Actual visible Godot
60-tick run took 1540 ms for 59 ticks (~38.3 simulation ticks/s). Ten-animal
60 Hz remains FAIL. Read docs/validation/BRIDGE_PROFILE.md for measurements.

2026-11-15 torsion slice: each rod segment now owns a material roll angle and
angular velocity with a tapered section inertia. Neighboring relative roll
is solved by XPBD compliance, anchored at the root. Z/X plus an arm key commands
opposite torsion; Godot receives and applies solved material roll. Build and
CTest 2/2 PASS, 10-animal active twist native p95 4.87 ms over 600 measured
ticks, 10-animal Godot passive smoke 60 ticks PASS but ~37.5 simulation ticks/s.
This is not full orientation-based Cosserat: no coupled shear/bending material
frames or torque reaction into torso. See docs/validation/TORSION_SLICE.md.

2026-11-15 bending follow-up: accumulated XPBD multiplier per arm/inner node
for three-component centerline curvature constraint, reset each actual substep.
Four vs sixteen solver sweeps targeted response fixture PASS, Release CTest 2/2,
2-animal 10,000-tick soak PASS. Ten active twist+bend native mean/p95
4.48/4.86 ms; visible Godot 10-animal 60-tick scene PASS but 37.9 ticks/s.
Two-animal active original-model scene showed arm bend and nonzero material
roll ~1.35 rad after 60 ticks. Full rotational Cosserat and 60 Hz still open.
See docs/validation/BENDING_XPBD.md.

2026-11-15 torso torsion coupling: first arm material-roll constraint now
uses the deforming torso up-axis and applies opposing mass-weighted position
corrections to two torso nodes. Isolated opposite-twist fixture body-node
difference ~1.15 mm and last-tick total angular momentum residual
~3.17e-9 kg m²/s. CTest 2/2, 10,000-tick soak PASS; 10-animal active twist
native p95 5.04 ms. Godot two-animal active input PASS, ten passive display
60 ticks PASS at 34.4 simulation ticks/s. This is still an approximate
scalar torsion coupling, not full orientation Cosserat or 60 Hz.
See docs/validation/TORSO_TORQUE.md.

2026-11-15 asynchronous bridge update: Godot reader thread now sends the next
native step on a 16.667 ms clock using the latest main-thread input, and the
renderer consumes completed authoritative C++ snapshots. Render-only JSON uses
six significant digits; C++ physics remains double. GPU 10-animal spread-active
600-tick test: 59.965 simulation ticks/s, 1191 visible frames/9.99 s, p95
frame interval 8.333 ms. Three dense-active 600-tick repeats: 59.766, 59.964,
60.001 ticks/s; frame p95 8.639/8.333/8.333 ms. Earlier dense run also
59.713 ticks/s. One additional run ended after tick 1 without a completion
record; cause unresolved. Runtime performance is PARTIAL for the tested scene,
not a 10-animal worst-case guarantee. Reset during dense-active run observed
and 600 further ticks completed. Build and CTest 3/3 PASS including bridge
protocol errors/dense reset. Read docs/validation/ASYNC_10_PERFORMANCE.md.
Follow-up: watchdog now uses time since last validated response, and a forced
native-child termination at tick 20 produced an explicit Godot exit code 2.
The earlier incomplete run remains unexplained, but future silence is bounded
by a 15-second timeout. Normal two-animal smoke still exits zero.

2026-11-15 swept contact checkpoint: shared C++ particle contact now tests
relative linear sphere sweeps over the substep and caches swept broadphase
bounds per solver pass. Analytic crossing and 200 N s two-prop regression
PASS; 400 N s order retention FAIL, so general CCD is not validated. Release
build and CTest 3/3 PASS; 2-animal dense 10,000-tick soak 0 nonfinite.
Ten-animal dense active native 600-tick mean/p95 6.587/7.024 ms; Godot GPU
600 ticks exited zero with screenshot, but 56.081 simulation ticks/s misses
the 60 Hz target. See docs/validation/SWEPT_CONTACT.md. Next: robust TOI
response/whole-shape collision, dense contact/skin optimization, tissue model.

2026-11-15 dynamic prop sweep guard: an enclosing-sphere center sweep and
post-constraint center separation now make the 400 N s two-prop straight-line
regression PASS for order, center gap and total momentum. Parallel near miss
PASS, Release CTest 3/3 PASS, 2-animal 10,000-tick and 10-animal 600-tick
native runs have zero nonfinite. Godot 10-animal dense active 600-tick runs
twice succeeded at 58.611 and 58.544 ticks/s, but two earlier runs hit the
15-second response watchdog. Runtime reliability and 60 Hz remain open.
Watchdog errors now include last tick/request/response IDs. This proxy does
not constitute exact oriented-box or deforming-surface CCD. See
docs/validation/RIGID_SWEEP_GUARD.md.

2026-11-15 bridge stall trace: 4/4 additional 10-animal 600-tick GPU runs
exited zero at 57.544–58.772 ticks/s. A 200 microsecond polling trial had
one 15-second watchdog failure at displayed tick 433 (request 435, response
434) and one successful run; polling change reverted. Blocking `get_line()`
trial failed at two-animal reset and was reverted. Three direct C++ server
600-tick active streams passed (~97 ticks/s). Reader and child liveness are
now included in future watchdog errors. Root cause remains unresolved; see
docs/validation/BRIDGE_STALL_TRACE.md.

Additional bridge evidence: one later 10-animal 600-tick run timed out at
tick 276, with request 278 outstanding and both the Godot reader thread and
C++ child alive. Pending bookkeeping was corrected; reader phase and byte
availability are recorded on future watchdog failures. Six instrumented
repeats then passed, 56.833–58.547 ticks/s. No phase-level failure captured;
reliability and sustained 60 Hz both remain failing gates in these tests.

2026-11-15 input path follow-up: headless Godot `game.input` CTest injects
Tab/Q and mouse pick/motion for animal 2, then checks C++ snapshot motion.
Display-only UI mouse interception was fixed. Release CTest 4/4 PASS;
120-tick run measured arm relative-tip divergence 0.164 m and horizontal
body motion during drag 0.774 m. This covers the synthetic two-animal path,
not a manual playability/attachment audit. See docs/validation/GODOT_INPUT_PATH.md.

2026-11-15 soft arms draft PR #1: increased C++ rod default 16 -> 24,
made section masses resolution-aware, relaxed position/director bend,
and added solver-side phased 3D idle curvature waves with manual-input
suppression. Godot demo enables the waves by reset protocol, with
--no-wriggle/--segments=N controls. First GitHub Actions Linux Release
build/CTest/two-animal benchmark PASS on 3026df96. Windows Godot visual
and sustained 10-animal 60 Hz remain unverified for the new settings.

2026-11-15 soft-arm native verification (draft PR #1, c36672b): GitHub
Actions Linux build / CTest 3/3 PASS; 2 spread-active solver mean/p95
1.770/1.825 ms, 10 dense-active 15.054/16.014 ms, no nonfinite.
Performance measurements exclude Godot; no 60 FPS claim. Godot GUI
validation and Windows MSVC test still pending.

2026-11-15 Windows CI: MSVC Release build and native CTest 3/3 PASS
on d80aefe (GitHub Actions run 43624588378). Godot original-asset
visual assessment and 60 Hz end-to-end GPU test remain open.

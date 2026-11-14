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

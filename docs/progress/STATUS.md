# Current status — 2026-11-15 (Asia/Seoul)

G0 baseline PARTIAL: old source inspected read-only; original dirty tree retained.
New independent repo OCTO_REBUILD, base cf42649, separate Sol/Terra worktrees.
No code is copied from the old solver. Original GameReady art will be reused locally.

Implementation underway, no phase declared complete. Sol owns XPBD world,
Terra owns bridge/render/input, Astra owns API/build/integration/performance.
No current build/test/visual/performance pass yet.
Targets: 1-animal real native/Godot vertical slice, then 2 shared-world animals,
then measured 1/2/5/10 load. Full 10-animal 60 FPS and physical feature completeness
are separate, unproven gates. First prototype is not full Cosserat or anatomical tissue.

Original failure lessons: global nonlinear solve had high active-input latency;
normal selection and endpoint contact caused regressions; body/skin mapping hid
physical gaps. New benchmarks include active inputs, reports expose contact/skin
limitations, and deterministic scenarios replace incompatible old binary checkpoints.

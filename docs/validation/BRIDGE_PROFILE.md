# Bridge and renderer experiment — 2026-11-15

Ryzen 5 5600X, Godot 4.6.2 OpenGL compatibility, 1280×720, 10 original GameReady model instances, native MSVC Release server. Each entry is one passive 60-tick run; no p95 frame distribution was measured. Active native benchmarks are in `INITIAL_RESULTS.md`.

| Protocol and read strategy | Last 10-animal response elapsed | Notes |
|---|---:|---|
| Full JSON, one pipe read per frame | ~265 ms | Initial screen run, unused segment data transferred. |
| Full JSON, drain currently available bytes | ~225 ms | Pipe response still spread across frames. |
| Render-only JSON, main-thread drain | ~80 ms | Only centers, arm nodes, prop poses and UI diagnostics. |
| Render-only JSON, 8-digit precision, main-thread drain | ~53 ms | Ten-animal reset response ~37,919 bytes. Precision affects transport, not double-precision C++ state. |
| Render-only JSON, background pipe reader, cached bone lookup | ~19 ms | Last-frame parse ~0.7 ms, skin update ~6.2 ms, solver ~4.2 ms. |

Actual visible Godot scene: 1 animal advanced 59 ticks in 531.5 ms (111.0 simulation ticks/s), 2 animals in 545.0 ms (108.3 ticks/s), 10 animals in 1540.3 ms (38.3 ticks/s). These are simulation throughput numbers, **not rendered FPS**. The loop currently requests a fixed `1/60 s` physics step after each response without wall-clock pacing or render interpolation. Thus ten animals do not meet 60 Hz in this scene. `ten_animals_optimized.png` confirms original model loading and posing at tick 60, not skin/physics accuracy.

Build and CTest 2/2 passed after C++ protocol change. Local logs are `work/tps1.out`, `work/tps2.out`, `work/tps10.out`, `work/gpu10.out`; generated `work/` is ignored by Git. Physical twist, anatomical body, continuous contact and gameplay controls remain outstanding gates. Next: in-process GDExtension or measured binary/shared-memory transport, wall-clock accumulator and true frame timing. The current text bridge remains a reproducible fallback.

After the transport run, targeted native fixtures were added and CTest 2/2 rerun: two initially overlapping animals in zero gravity/floor/damping both move, report cross-animal contacts and preserve total linear momentum within 1e-5 kg·m/s after 20 steps. A separate capped force on an arm tip creates actual animal–dynamic-prop contacts and moves at least one prop during 120 steps. The latter uses an external force, so total momentum conservation is not asserted there. These tests cover particular fixtures, not all contact configurations or rotational angular-momentum accuracy.

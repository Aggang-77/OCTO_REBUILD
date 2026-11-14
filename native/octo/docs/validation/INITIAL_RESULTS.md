# Initial rebuild evidence — 2026-11-15

## Scope and reproducibility

Independent repository `OCTO_REBUILD`; original checkout `OCTO` remains at `b599085216a55a7665b73acb9858856db023d4ee` on `feature/P2V-jelly-shared-world`. Before/after SHA256 comparison of its 364 source, document and asset files found no changes. The original GameReady GLB (15,203,672 bytes, 193 joints) was copied locally for rendering; its provenance and public distribution rights remain unverified.

Initial positional XPBD prototype: 16 segments per arm, 8 arms, coarse 7-node body and volume tets, particle boxes, sphere contact, capped force drag, tip attachments, fixed 1/60-second ticks with four substeps. Parameters are assumed engineering values, not measured octopus tissue. Physical twist, elliptical local flattening, anatomical mantle, continuous collision detection, GPU skin/physics error bounds and rigid-body angular inertia remain unimplemented. The displayed skinned GLB is approximate.

Windows, Ryzen 5 5600X, MSVC 19.43, CMake 3.31.7, Godot 4.6.2, OpenGL compatibility, 1280×720. CPU physics measurements are from a native Release executable. Run `./tools/build.ps1`, `./build/release-final/octo_integration_tests.exe soak 2 10000`, `./build/release-final/octo_benchmark.exe 10 600 dense`; to view the live scene run `./tools/run-demo.ps1 -Animals 2` after the Godot asset import (`godot --headless --editor --import --path game`).

## Measured gates

| Check | Result | Evidence and limit |
|---|---|---|
| MSVC Release build; CTest | PASS | 10 targets built; 2/2 CTest. CMake try-compile `/Zi` hit MSVC C1902 in this environment; the build script pins compiler and skips the probe. Direct MSVC unit executable also passed. |
| 10,000 ticks, two animals | PASS | Exact tick count, finite sampled state; sampled maximum penetration 14.4 mm, body volume error 0.00351. Sampling every 30 ticks does not prove an unsampled bound. |
| 1/2/5/10 native active load | PASS for measurement | See `benchmark_raw.csv`: mean 0.45/0.80/1.94/4.29 ms and p95 0.56/1.00/2.16/5.10 ms, 600 measured ticks each after 120 warmup. Step time excludes snapshot copy, Godot, serialization and render. |
| 10 dense active load | PASS for measurement | `dense_10.csv`: mean 5.50, p95 5.93, p99 6.91 ms. Max sampled pre-solve overlap 14.9 mm; body volume error 0.00719. |
| Godot live two / ten | PARTIAL | `two_animals.png` / `ten_animals.png` show actual original GLB scenes at tick 60, model loaded 193 bones. User input not exercised by GUI automation; no full frame-time or render GPU measurement. |
| 10 animal real-time 60 FPS | FAIL | Last-frame Godot RPC response latency ~264.8 ms for ten animals (~55.8 ms for two); synchronous text protocol/state transfer and frame scheduling bottleneck. Screenshot scene proves display only, not smooth frame rate. |
| Full physical fidelity | NOT TESTED / unimplemented | No physical twist, transverse arm cage, fine mantle, skin tracking threshold, robust CCD. Contact counts include floor and self contacts; they do not alone establish bilateral animal/prop reaction. |

Next: compact binary/shared-memory or native GDExtension transport and quantify renderer costs; isolate cross-animal and dynamic-prop impulse tests, make all quaternion/radius fields finite checks, distinguish pre-solve penetration from residual; add orientation-based Cosserat twist and local volume cage, then actual 10-animal frame budget and playable controls. Do not declare Phase 1–7 accepted on this prototype.

# 10-animal asynchronous Godot bridge — 2026-11-15

## Change

The initial UI waited until the next render update to send every new physics request, limiting ten-animal throughput to 34–38 fixed ticks/s despite native physics taking about 5 ms. A dedicated pipe reader now schedules the next versioned request at `1/60 s` independently of rendering. Godot's main thread publishes current arm/drag input and applies the latest complete C++ snapshot. Exactly one native request is in flight. JSON is render-only and six significant digits per number; the native solver remains double precision. This is a transport/visual precision choice, not a validated skin error bound. The renderer does not interpolate consecutive states yet.

## Observed runs

Windows, Ryzen 5 5600X, RTX 4060, Godot 4.6.2 OpenGL compatibility, 1280×720, original 193-joint GameReady model, MSVC Release, 16 rod segments × eight arms × ten animals. `render_frames` counts `_process` calls and `wall_p95_ms` is the 95th percentile of Godot `delta` among frames after the first simulated tick. `effective_sim_tps` divides 599 fixed steps by elapsed wall time from tick 1 to 600. These are separate measures; a single last-frame RPC time is not a frame-time percentile.

| Scenario / run | 599 steps elapsed (ms) | Simulation ticks/s | Render frames | Render interval p95 (ms) | Frames over 16.667 ms |
|---|---:|---:|---:|---:|---:|
| Spread passive | 9981.4 | 60.011 | 1176 | 9.091 | 5 |
| Spread, all 80 arms active | 9989.2 | 59.965 | 1191 | 8.333 | 1 |
| Dense, all arms active, initial | 10031.4 | 59.713 | 1186 | 9.091 | 2 |
| Dense, all arms active, repeat 1 | 10022.4 | 59.766 | 1194 | 8.639 | 1 |
| Dense, all arms active, repeat 2 | 9983.2 | 60.001 | 1191 | 8.333 | 2 |
| Dense, all arms active, repeat 3 | 9989.0 | 59.966 | 1191 | 8.333 | 2 |

The dense scene uses 1.0 m animal spacing and three dynamic props. All 80 arms receive fixed bend and positive twist activation. It is not the worst-case moving contact or self-collision workload; the input is a deterministic stress case, not human play. The original asset is visibly loaded at tick 600 in `async_active_10.png` and `async_dense_active_10.png`. Two first animals can be obscured by the debug overlay. A separate run issued a reset during the dense active workload, observed native tick zero, and completed 600 more ticks at 59.815 ticks/s with frame p95 9.091 ms.

One attempted second repeat exited or stopped producing output after tick 1, with no Godot error text or completion record. That run is **unresolved**, not counted as a pass. Three subsequent bounded repeats and a reset run completed. The root cause might involve process lifecycle or the environment; evidence is insufficient to assign it. Longer continuous gameplay, GPU timing, adversarial collision performance, actual keyboard/mouse handling, and physics/skin mismatch thresholds remain NOT TESTED. Full orientation-based Cosserat shear/bending and local cross-section deformation remain unimplemented.

After that unexplained run, the bridge watchdog was changed to check elapsed time since the last validated response, including when a worker has already sent the next request. An intentional native-child termination test at tick 20 exited Godot with code 2 and `Native solver exited`; an ordinary two-animal 60-tick run still exited zero. This validates one failure path and prevents indefinite silence after 15 seconds. It does not explain or retroactively pass the earlier incomplete run.

## Reproduce

```powershell
./tools/build.ps1
$env:OCTO_SERVER = (Resolve-Path ./build/release-final/octo_server.exe).Path
$env:APPDATA = (New-Item -ItemType Directory -Force ./work/appdata).FullName
$env:LOCALAPPDATA = (New-Item -ItemType Directory -Force ./work/localappdata).FullName
& C:\Tools\Godot\godot.exe --path ./game -- --animals=10 --dense --test-all-active --benchmark-ticks=600
```

For an interactive scene use `./tools/run-demo.ps1 -Animals 10` after importing the GLB. CTest now runs `physics.unit`, `physics.integration` and `bridge.protocol`; all **3/3 PASS** on this machine. The Python protocol test covers optional dense reset spacing, rejected invalid config and duplicate IDs, and one full step/roll snapshot. The original checkout remains untouched.

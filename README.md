# OCTO rebuild

Independent 3D octopus simulator prototype. The original repository is preserved at `../OCTO`; this repository does not import its physics solver. It reuses the user-provided GameReady model as a local render asset. Read `docs/validation/INITIAL_RESULTS.md` and `docs/progress/STATUS.md` before extending it.

On Windows with MSVC, CMake, Ninja and Godot 4.6.2:

```powershell
./tools/build.ps1
C:\Tools\Godot\godot.exe --headless --editor --import --path game
./tools/run-demo.ps1 -Animals 2
./build/release-final/octo_benchmark.exe 10 600 dense
```

The two-animal live scene uses Q W E R A S D F for eight independent arm activation inputs, Tab for animal selection, Ctrl for attachment and left-drag for capped force picking. The physics remains an XPBD approximation rather than a full Cosserat rod. The asynchronous bridge reached 60 Hz simulation and over 60 visible frames/s in the measured 10-animal spread scene; dense active simulation remained close to 60 Hz. See `docs/validation/ASYNC_10_PERFORMANCE.md` for evidence, the one incomplete repeat, and remaining physical work.

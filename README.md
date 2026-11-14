# OCTO_REBUILD — octopus simulator (main)

C++ shared-world XPBD physics with a Godot 4.6.2 render client. This
repository is independent of the preserved historical `../OCTO`
project. The untracked original GameReady model remains a local asset
at `game/assets/Octopus_GameReady_v5.glb`.

## Windows launch

```powershell
.\tools\build.ps1
.\PLAY_DEMO.cmd
```

Godot must be installed at `C:\Tools\Godot\godot.exe`.
Click the Godot window to focus it. Tab switches between octopuses;
left mouse drag applies bounded force, right mouse drag orbits the
camera, and F5 resets.

## Game controls v1.0

| Torso-relative arm | Extend (hold) | Stroke backward (hold) |
|---|---|---|
| Left front | F | D |
| Right front | J | K |
| Left side-front | S | A |
| Right side-front | L | ; |
| Left side-rear | R | E |
| Right side-rear | U | I |
| Left rear | W | Q |
| Right rear | O | P |

Let go of extend to retract/curl, let go of stroke to return
toward the front. Both inputs are independent, so F+D together
extends and paddles the same arm.

**Space** immediately releases every suction contact. While held,
automatic gripping stays disabled. Upon release a short re-grip
cooldown applies. Retracting a floor-attached arm peels contacts;
a gripped movable object remains held during retraction unless
Space is used or the attachment breaks. Release does not reset
the object's velocity.

See [the controls specification and simulation caveats](docs/design/CONTROL_V1.md).

The main branch does **not** include the abandoned expensive jelly
shader/membrane experiment. Original skeleton skin is retained.
The automatic suction/contact implementation uses coarse discrete rod
sites, not full anatomical sucker surface mechanics.

## Tests

```powershell
.\tools\build.ps1
ctest --test-dir build/release-final -C Release --output-on-failure
```

GitHub Actions also tests Linux, Windows, and a native Godot
synthetic-key input path. The original GameReady model is not stored
in Git, so final visual/gameplay acceptance and FPS with the original
asset require a local Windows demo run.


## C++ bridge version mismatch (`bad_operation`)

Controls v1.0 sends `step2`; an `octo_server.exe` compiled before this
protocol existed will reply `bad_operation` even if `reset` succeeds.
`PLAY_DEMO.cmd` / `tools/run-demo.ps1` now detects outdated native
binaries, rebuilds them when necessary, and probes a disposable native
server using a real `step2` request before launching Godot.

For a manual rebuild or when launching Godot independently:

```powershell
.\tools\build.ps1
.\tools\check-bridge.ps1 -Server .\build\release-final\octo_server.exe
.\PLAY_DEMO.cmd
```

Close any older running Godot/server process first, since Windows may
prevent replacing an executable while it is running. The expected
probe output begins with `BRIDGE_V1_PREFLIGHT_PASS`. If validation
fails even after recompilation, check `OCTO_SERVER` is pointing to
the repository's newly built executable.

## Stronger octopus arms / grips

Default C++ arm stroke motor force/gain is now **4×** the earlier
baseline (`WorldConfig::arm_motor_strength=4.0`), and the automatic
sucker/legacy tip break thresholds are **3×** stronger
(`WorldConfig::sucker_strength=3.0`). The 16-key controls are unchanged.
These are force/threshold multipliers, **not guaranteed 4× travel**;
contact, mass, friction and the number of attached suckers also matter.
The values are bounded in `WorldConfig` and checked by the native
control regression suite. Rebuild the native server with
`./tools/build.ps1 -NoTests` before running the Godot demo.

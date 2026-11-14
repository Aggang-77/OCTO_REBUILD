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

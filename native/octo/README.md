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

## Slime surface, progressive uncoiling, anti-flip (2026-11-15)

- Imported GameReady GLB materials receive a **lightweight wet PBR
  finish** (roughness 0.20, clearcoat 0.68, clearcoat roughness 0.10).
  Original albedo/normal textures stay intact; there is no animated
  jelly shader, per-frame re-meshing or simulated mucus fluid.
- Pressing an arm's extension key advances a continuous **base-to-tip
  uncoil front**. Releasing the key coils the arm back progressively.
  The distal sections retain target curvature until the front reaches
  them, rather than instantly turning the whole rod straight.
- A contacted rigid object/floor supplies a **contact-local frame**.
  Nearby ungripped suction sites are steered toward the local surface;
  adhesion itself still requires actual C++ contact and can break.
- Torso upright bias applies capped, equal-and-opposite forces to
  real torso mass nodes, reducing unintended flips without locking the
  body or overriding collisions.
- The previous overpowered arm motor 4.0 and suction 3.0 multipliers
  are reduced to **2.2 / 2.2**. The eight dual-key pairs and Space
  release semantics remain unchanged.

**Fidelity note:** wrapped contact uses sphere-like local curvature
around sampled rigid particles, not a true arbitrary-mesh surface
geodesic; the wet appearance is PBR lighting, not a fluid layer.
Real GameReady GLB visuals and feel remain subject to local testing.

## Low-resolution viscoelastic flesh / mantle (2026-11-15)

The C++ solver now allocates **12 dynamic shell particles per animal**
(two rings of six) around the original seven-vertex torso cage.
They have physical mass, contact with ground and props, and
compliant strands to the body. The original tetrahedral body volume
constraints remain active.

Each of the 16 segments of each arm additionally carries a
**damped dynamic transverse strain** driven by measured contact
compression and smoothed along neighboring sections. The two
principal axis scales are inverse pairs so their product remains
one; axial stretch also changes area through the existing
section-volume correction. The physical strain has a slow recovery
and local viscous damping rather than snapping back in one frame.
Strain is applied through the existing GPU-skinned GameReady arm
bones, with the previous restrictive ±1.8 visual scale expanded
to 0.40–2.5. **No new jelly shader or 5k-vertex CPU mesh rebuild**.

The bridge transmits all 19 body mass-node positions and 2-axis
section strain data. If the imported GLB exposes a **separate named
mantle/head/hood mesh**, Godot uses the physical shell bounds to
rescale its existing mesh transform (no rebuilt vertices); a
combined/unnamed GLB cannot receive that mantle visual deformation
until its model is split or painted with suitable vertex weights.
This is a coarse shape/viscoelastic proxy, **not full FEM or
Navier–Stokes slime fluid**; its discrete shell particles do not
provide exact triangle-to-triangle surface collision.

**GameReady combined mesh correction:** original recorded GLB has **193
bones** (192 arm bones plus a shared torso root). In addition to
separately named mantle meshes, the renderer now scales the **shared
torso root bone** from the low-resolution shell's measured bounding
axes and compensates the child arm bones with parent-space targets.
This makes root-weighted mantle vertices deform even when the GLB is
one combined mesh. Other vertices only deform according to their
original skin weights, so full local mantle folds still require a
re-rig or a multi-point weighted soft skin.

A momentum-conserving internal dashpot damps shell-to-cage relative
velocity before integrating particle positions, reducing rubbery
oscillation without injecting external forces. The shell is only
12 colliding mass points (not a watertight volumetric tetra mesh).

## Delayed material creep and stress relaxation

When you hold an arm against the terrain or pull it with the mouse,
C++ now slowly adapts the stress-free arm length/bend shape and the
mantle-shell strand rest lengths. This reduces the mechanical tendency
to snap immediately back to the originally rigged rest pose.
It is distinct from the previous viscous damping: **viscosity** removes
oscillations; **creep** changes internal rest shape under sustained
strain, and **stress relaxation** reduces the remaining elastic strain
under constant deformation. On release, slow recovery acts instead
of permanently freezing the octopus's shape. Per-segment measurements
are available in the bridge as `creep` and `elastic_strain`.
All calculations remain in the shared C++ world; GPU skinning remains
unchanged. This is an approximate and bounded gameplay material,
not a measured biological viscoelastic constitutive model.

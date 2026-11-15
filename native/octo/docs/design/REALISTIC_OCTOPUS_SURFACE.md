# Living Octopus — original GameReady mesh skin pass

## Biological design target

An octopus is **not a homogeneous slime blob**. Its arms are near-volume-
conserving *muscular hydrostats*, with active longitudinal, transverse and
oblique/helical muscles. Bending, extension, torsion and stiffness are
regulated through selective muscle activation. The skin has pigment cells,
iridophores and actively shaped papillae, which are separate from the
underlying gross tissue motion.

Sources:
- Kier & Stella, *The arrangement and function of octopus arm
  musculature and connective tissue*, J Morphol, 2007,
  DOI 10.1002/jmor.10548.
- Review, *Biomechanics, motor control and dynamic models of the soft
  limbs of the octopus and other cephalopods*, J Exp Biol, 2023,
  DOI 10.1242/jeb.245295.
- Allen et al., *Comparative morphology of changeable skin papillae in
  octopus and cuttlefish*, J Morphol, 2014, PMID 24741712.

## Implemented in this pass

1. **Original GLB mesh vertex deformation**, not an overlay tube:
   `game/shaders/octopus_skin.gdshader` reads the imported skeleton's
   four bone indices and weights for each original vertex. It samples
   256-element per-bone fields from the native C++ bridge; under loaded
   skin it moves downward-facing vertices inward and lateral vertices
   outward. The original skeleton continues to move the entire model.
   GPU skinning remains in use; no large CPU remeshing each frame.
2. `game/scripts/octopus_skin.gd` maps original bone names A0_00...A7_23
   to solver arm IDs (reverse arm ordering), then samples the
   transmitted physical `tissue` and `creep` variables every tick.
   It maps **by actual bone index** instead of assuming a fixed order.
3. Preserve original **albedo, normal, roughness and metallic texture**
   channels when converting Godot StandardMaterial3D to a ShaderMaterial.
   Special/nonstandard/transparent materials are intentionally left
   untouched rather than silently destroyed. Mesh-wide overrides are
   handled too.
4. Add small nonoscillatory micro-papillae in the actual surface
   geometry, heterogeneous roughness and gentle chromatophore-like color
   modulation. These approximate visible effects; they are not a
   simulation of individual chromatophores or muscles.
5. Make default passive posture **asymmetric and lightly curled** rather
   than all eight arms forcibly shortened, tightly coiled and actively
   sweeping every single tick. The 16 reach/stroke keys and Space release
   remain unchanged. Held active muscles still reach/grip as before.
6. A small, slow mantle-breathing pose supplements the 19-node C++ mantle
   shell deformation without a high-frequency spring effect.

## How to run / troubleshoot

The normal `PLAY_DEMO.cmd` enables GPU mesh skinning by default, using
the existing **local, untracked** GameReady GLB. To compare with the old
PBR/bone-only behavior:

```powershell
$env:OCTO_SKIN_MODE = "legacy"
.\PLAY_DEMO.cmd
Remove-Item Env:\OCTO_SKIN_MODE
```

To report exact source mesh topology, materials and skinning coverage:

```powershell
python .\tools\audit_gameready_mesh.py .\game\assets\Octopus_GameReady_v5.glb
```

Godot prints `NATIVE_MESH_SKIN animal=N covered=X skipped=Y` during
startup. If `covered=0`, imported source materials are not supported
by this conversion. Review the audit output. The default game remains
playable and opaque custom-shader materials are not overwritten.

## Fidelity / performance boundaries

- **Shader deformation does not change native C++ collision geometry.**
  The visual displacement is bounded and physical arm pressure driven,
  but cannot replace proper full triangle/edge contact, volume
  preserving FEM, or a mesh-embedded deformable skin driven by a stable
  volumetric solver.
- The previously built four-point tetra ring experiment remains
  off by default: a two-octopus stress fixture reached soft-tetra
  relative volume errors above 3.0 (severely distorted). Turning it
  on globally would be unsafe regardless of an attractive screenshot.
- The actual GameReady GLB is **not tracked in GitHub**. CI tests use a
  real Godot OpenGL renderer, a synthetic textured surface and native
  bridge physics, but cannot inspect or visually validate the user's
  private original GLB; the first local graphical playtest is required.
- Source mesh vertex counts and manifold/skin topology can be checked
  locally with `audit_gameready_mesh.py`. For high-fidelity contact,
  the longer-term physics path is to generate a **low-resolution,
  noninverted tetrahedral cage from the actual source surface**, embed
  original vertices in it and solve contacts in the same C++ world.
- Shader parameters/pressure follow the original **real native tissue
  state**; any additional wet specular breakup is visual. No claim of
  physically accurate skin microstructure or verified GPU FPS.

## Acceptance checks

- Linux and Windows CTest continue passing.
- Godot's real-key-input test constructs a textured StandardMaterial3D,
  installs the real shader, verifies authored color/roughness texture
  bindings and the actual imported bone-index lookup, and checks
  asymmetrical idle posture plus respiration.
- If the user's original GLB imports without StandardMaterial3D or has
  over 256 skeleton bones, the program reports the limitation rather
  than dropping the original material.

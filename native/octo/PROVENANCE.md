# Mantle-balloon integration

The integrated game uses `songhh06/OCTO_REBUILD` branch
`fix/contact-mantle-balloon` at `9a2a7df438bb5098b9f8492bbb55897c96fb52c4`.
The remote ref was verified with Git before importing it. Its history is a
parent of the local merge, alongside the existing integrated game history.
The previous selective-arm prototype is preserved in checkpoint `c8ba4b7`
and is superseded by this branch's movement and controls.

## Source authority

The source arm controller and GPU skin shader are copied unchanged. The skin
module changes only its resource path. The renderer retains the source model
yaw, arm mapping, mantle normalization and deformable interarm web.

The source grounded profile is used: `grounded_rest=true`,
`tissue_stiffness_ratio=0.2`, `spawn_height=0.27`, `upright_strength=0.08`,
`auto_suction=true`, one animal and no native demo props. The original
reach/seal/pull/release controller, passive flesh, friction, suction, mantle
chambers and mantle/web/root constraints are retained without movement tuning.
Space enables floor suction only on actively commanded arms; Space-up clears
floor suction independently of object grabs. The latest source adds clicked
targets, Shift+arm approach/grab, Ctrl+arm release, Ctrl-alone release-all,
Alt+left-drag and wheel zoom. Grabbed arms lock other muscle commands until
released. Native proximity-grab logic is retained unchanged.

The map, hunters, character physics, difficulty selection, ten-second continuous
capture objective, reset/pause and secret fight transition remain from the
integrated game. A carried hunter uses its existing finite spring bindings.
An established hunter hold persists after releasing the arm key and Space;
Ctrl releases it. Occupied arms cannot also grip native ground. Hunter target
approach and distal wrapping use bounded forces with opposite body reactions;
acquisition uses the source physical radius and 0.035 m proximity gap, separately
from the larger grounded contact envelope. Ctrl+Shift without an arm remains
reserved for the existing secret-mode chord.

## Integration boundaries

`core/scene_coupling.inl` adds registered terrain/triangle contact, per-site
scene forces/planes, reaction impulses, contact metadata and an external
floor-grip exclusion mask. Without registered terrain or scene inputs the
source flat-floor paths are unchanged. These hooks do not replace the source
muscle/controller or mantle/web algorithms.

The `game_server.cpp` adapter exposes `game_reset5` and `step6`. It applies the
uniform compatibility transform `world = origin + 1.5 * native` to snapshots,
geometry and contacts. Forces enter divided by scale and reaction impulses
leave multiplied by scale. Drag stiffness is unchanged, and its force cap is
converted by scale. No geometry/mass/inertia multiplier is applied inside the
source engine. This retains the source simulation profile while keeping the
larger integrated octopus and its contact envelope.

Static Godot map shapes are uploaded as world-space triangles and indexed by
native BVH. Hunters and dynamic props retain Godot/Jolt physics; bounded spring
loads and contact reactions cross the adapter. This is explicit coupling between
two solvers, not a migration of all character dynamics into C++.

## Current verification

For the 9a2a7df update, checks were limited to the changed octopus integration:

- Production native executable rebuilt successfully with Zig 0.13.0. A direct
  startup/snapshot request reported the expected source commit and exited cleanly.
- Source input parity: 15 focused checks passed, including target selection,
  Shift attack, Ctrl release, grabbed-arm locks and the step6 target trailer.
- A five-step native fixture passed external-grip lock/release, physical versus
  grounded radii, and dynamic contact clearance checks.
- A transport-only Godot fixture passed ordered reset/mesh-begin/mesh-commit
  replies with geometry_ready=true. The initial reset is now queued before the
  pipe worker starts, and that worker owns every live pipe write.
- One actual-map startup check passed five assertions: 99,825 collision
  triangles uploaded, native time advanced, source identity/scale/radii matched,
  and a real hunter target was selected and accepted by step6. Initial setup
  took about 16 seconds; no long capture fixture was run.
- Unchanged map, character, secret fight and broad physics suites were not rerun.
  A complete gameplay session and ten-second physical capture with this source
  have not been verified.

## Historical verification (8bb7434 integration)

On Windows with Zig 0.13.0 and Godot 4.7.2:

- The original 8bb7434 executable and integrated native executable produced
  exactly equal serialized movement for 360 frames under identical commands,
  including source suction toggles, asymmetric input and bounded drag.
- Source controls/skin parity: 18 checks passed, including native-time phases.
- Adapter protocol: 129 requests passed, including atomic triangle upload,
  origin/scale conversion, source identity, active-only suction and carry masks.
- Godot integration passed 125 checks and secret-fight isolation passed 24.
  Real hunter acquisition, carry after arm-key release and Space-up release
  were observed. A complete ten-second physical hold with the new source
  remains unverified: later acquisition/reacquisition fixture attempts did
  not complete, and further runs were stopped at the user's request to
  minimize testing. The superseded prototype's victory screenshot is not
  evidence for this source version.
- Native physics, viscoelastic, volumetric-arm, integration and scene-coupling
  suites passed. Scene coverage includes actual raised/slope mesh contact,
  loads/reactions and floor-mask exclusion with native object-grip retention.
- Two unchanged upstream suites fail identically against both original and
  integrated physics: `controls_v1_tests` still expects idle-arm suction under
  Space despite the later active-only rule; `contact_mantle_tests` still expects
  passive rear proximal forward projection greater than -0.02 m (the original
  reports -0.0907439 m). These failures are retained and are not hidden by
  changing the authoritative movement or lowering assertions.

Run `tools/build_octopus.ps1` to rebuild. `-Tests` also runs the source tests;
the two failures above were observed against the prior 8bb7434 source, not
rechecked for this update. Game integration fixtures are in
`tests/test_octopus_merge.gd`, `test_octopus_contact.gd` and `test_secret_fight.gd`.
This record does not establish biological fidelity, a maximum climb angle or a
real-time 60 Hz performance guarantee.

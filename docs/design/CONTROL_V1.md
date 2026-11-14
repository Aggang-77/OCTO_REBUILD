# Octopus Game Control Specification v1.0 — implemented keyboard/solver mapping

## Control basis

Player keys command the eight arms of the selected octopus. Each has an
independent **extend/retract** key and **stroke forward/back** key. All
directions are defined in the animal's torso frame, using the dynamic cage's
+Z forward vector and +Y up. The `Tab` selection toggle and mouse-force
drag from the technical demo remain available. No modifier keys are
required to use extension and stroke simultaneously.

| Body-relative arm | Solver index | Extend key | Stroke key |
|---|---:|---|---|
| Left front | 7 | F | D |
| Right front | 0 | J | K |
| Left side-front | 6 | S | A |
| Right side-front | 1 | L | ; |
| Left side-rear | 5 | R | E |
| Right side-rear | 2 | U | I |
| Left rear | 4 | W | Q |
| Right rear | 3 | O | P |

All suckers release: **Space** (hold suppresses reacquisition).

The physical arm root angles are spaced by 45°. For backward compatibility
with the original GameReady rig, the physical frame does not currently have
a separate exact ±22.5° front-pair rest alignment; left/right names are
approximate body-relative sector names. They are not screen-left/right.

## Extension key (held)

- Press: command muscle activation=1, curvature=0, axial rest-length
  ratio=1.28 (extend).
- Release: command activation=1, curvature=3.6 rad/m and length
  ratio=0.70 (retract/curl).
- A low-pass at the fixed physics substep (`1-exp(-12*h)`) drives
  both targets continuously. No pose teleportation.
- Attached to static floor: extending retains suction; retracting
  starts a sequential distal-to-proximal floor peel over roughly 0.22s.
- Attached to a movable rigid object: retracting leaves that suction
  attached and moves the gripped mass through the existing shared-world
  positional constraints, subject to break force. Note this is a
  simplified discrete particle grip, not true surface patches.

## Stroke key (held)

- Press: desired stroke=+1 (posterior relative motor target).
- Release: desired stroke=-1 (return anterior).
- The solver low-pass filters the desired stroke and moves arm
  segments toward body-frame ±π/3 yaw-shifted length-constrained
  targets using bounded spring forces. Each applied motor force
  produces an opposite reaction distributed to the torso cage.
- Stroke is independent from extension and does not require the
  extension key. This is a force-based approximate yaw sweep,
  not a precise physically constrained ±60° joint motor. The
  achieved angle and speed depend on inertia, collisions and grip.

## Automatic suction

Enabled by `reset ... AUTO_SUCTION=1` in the Godot v1 demo;
disabled by default in native `WorldConfig` to preserve historical
passive regression fixtures. Each arm has multiple discrete adhesion
candidate sites (roughly 5–7 along its distal half), using existing
rod nodes, *not* fully resolved anatomical suction cups.

Suction candidates are tested after contact resolution:
- Floor or movable-rigid proximity within about 1.4 cm of particle
  surface; geometric candidate site only, not exact skin contact.
- Approximate underside-facing normal must align with the target.
- Candidate node area must exceed a minimum; relative velocity
  must stay below a threshold.
- Contact must remain stable for at least ~32ms.
- Force limit scales with a proxy area; excessive force breaks
  individual sites and starts a cooldown.

Floor adhesion automatically releases sequentially when the
extension key is released. Movable-rigid adhesion persists on
retraction, but can peel under excessive load.

## Space release

- Space down: release *all* current grips in the C++ world and
  suppress reacquisition while held. It overrides legacy manual
  attachment requests as well.
- Space up: a ~180ms per-site cooldown prevents immediate re-grip.
- Space does not alter the extension or stroke targets.
- Releasing a moving object does **not zero its velocity**; it
  continues with the velocity already calculated by the C++ solver.
  No separate throw impulse is fabricated.

## Bridge protocol

The legacy `step` grammar is retained for old tests/scripts.
New `step2` grammar has **9 fields per arm**:
`animal arm activation curvature extension twist stiffness attach sweep`,
followed by the existing 9 drag fields
`kind index arm target_x target_y target_z stiffness max_force`
(actually **8 numeric drag fields**, as shown), and a single
`release_all=0/1` integer.
There are 8 arm entries for each animal, in solver index order.

New optional reset suffix:
`reset ANIMALS [SPACING [IDLE [SEGMENTS [ORGANIC [AUTO_SUCTION]]]]]`.

## Speed / rendering

- All custom jelly shaders and per-frame jelly/Web ArrayMesh rebuilding
  were removed from the active branch.
- With a local GameReady GLB, render only its skeletal arm bones.
- Without GLB, use a single shared `MultiMesh` per octopus with
  scaled sphere primitives per physical segment, StandardMaterial3D
  and one inexpensive mantle sphere. No custom shader.
- Interactive launcher defaults to **16 physical segments/arm**,
  down from 24 in the earlier jelly demo; native WorldConfig still
  defaults to 24 for historical test coverage.

## Fidelity and remaining work

- This is a gameplay-oriented v1, not a full anatomical octopus
  locomotion / sucker simulation.
- Adhesion surface, normal, area and peel are approximations at
  discrete rod nodes; there is no per-sucker mesh CCD, suction-pressure
  field, deformable membrane or grasp planner.
- The exact ±60° pose is a target, not a hard guarantee.
- Fine-grained selective release, robust multi-object handling
  and original GameReady GLB appearance need further validation.

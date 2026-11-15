# Contact-driven controls

The eight arm keys follow the octopus's body, with labels drawn over the
selected animal's arms. Camera orbit does not remap them.

| Arm | Key |
|---|---|
| Left front / right front | W / E |
| Left side-front / right side-front | Q / D |
| Left side-rear / right side-rear | A / C |
| Left rear / right rear | Z / X |

Hold one or several arm keys to repeat reach, actual grip, pull and release.
An arm waits for the authoritative C++ `attached` state before pulling. If
contact never happens, it retracts and retries after 1.5 seconds. Losing a
grip ends the pull. Releasing the key initiates peeling, then returns to
passive, asymmetric rest.

| Input | Action |
|---|---|
| Shift + arm | Reach continuously without entering the pull phase |
| Ctrl + arm | Reach/contact and brace without the stroke motor |
| Comma / period + arm | Opposite material twist targets |
| Arrow keys | Body-relative crawl assistance with staggered arm groups |
| Space | Immediately release all suckers; overrides every arm/modifier |
| Tab | Select the other octopus |
| Left drag / right drag | Bounded force picking / camera orbit |
| F5 | Reset the native world and control cycle clock |

Ctrl takes precedence over Shift if both modifiers are held. Manual arm
keys take precedence over the timed arm selection of the crawl assistant.
Arrow input selects arms and muscle targets; it never writes body position
or velocity. Sideways and backwards efficiency are not calibrated. Neither
the gait nor grip forces have been validated against animal kinematics.

The controller is advanced using simulation time. Repeated render frames
cannot accelerate the cycle. Per-arm states are retained separately per
animal and reset when simulation time resets. Native sucker acquisition
uses the same conservative floor support as native collision, and cannot
reacquire while extension is below the peel threshold.


## Two-hand control update (2026-11-15)

The current gameplay mapping supersedes earlier keyboard tables. Physical
left-hand keys R/E/W/Q drive arm indices 7/6/5/4, respectively; right-hand
U/I/O/P drive indices 0/1/2/3. Both hands operate simultaneously. Arrow-key
crawl assistance is disabled. Shift/Ctrl with an arm retain reach/brace,
Space releases suckers, and Tab changes the selected animal.

Reach/pull/release phase limits are reduced (0.75/0.32/0.16 seconds,
respectively; grip-dependent transitions can shorten phases further).
Command activation is reduced from 1.0 to 0.78, peak sweep force cap from
0.085 to 0.060 times configured motor strength. Unpressed arms have a weak,
body-relative, mirror-symmetric radial home force and no coordinate snapping.
The grounded torso has a bounded reaction-pair lift against supporting near-root
arm particles, and grounded octopus floor friction decreases while sliding.
These are gameplay approximations, not validated biomechanical parameters.


The top-down drawing maps the eight radial arms clockwise from the top:
`U` (arm 0), `I` (1), `O` (2), `P` (3), `Q` (4), `W` (5),
`E` (6), `R` (7). This mapping supersedes the previous Q/W/A/S and U/I/J/K scheme.


## Contact-gated push locomotion and mirrored skin mapping (2026-11-15)

Actual GameReady arm rendering was reported mirrored relative to the prior
keymap, so solver indices 0..7 now use physical keys R,E,W,Q,P,O,I,U.
This reverses the previous mapping while preserving the requested spatial
positions in the top-down drawing. The mesh-side correspondence still needs
an on-device visual check.

Holding a key cycles four contact-dependent phases:

1. `shorten` (0.18s): contraction target 0.90 and curvature 0.8.
2. `anchor` (max 0.42s): target 1.05, allowing middle/distal suckers to
   form a real floor/prop contact. Transition only after confirmed attachment.
3. `elongate` (max 0.34s): target 1.38 while the real anchor resists extension.
   This pushes the body by reaction through XPBD constraints, without a
   fabricated body force. Loss of attachment ends the powered stroke.
4. `release` (min 0.19s): target 0.76 to peel floor suckers before retry.

The actual cycle duration depends on contact and cannot be reduced to a fixed
rhythmic gait. Unpressed arms remain weakly driven to symmetric neutral rest.
Space forces all suckers to detach, Shift overrides to continuous reach and
Ctrl overrides to bracing. No unconditional body propulsion is introduced.


## Proximal-only bend safeguard (2026-11-15)

The previous whole-arm 120-degree kink correction was inappropriate:
real octopus distal arms must be able to coil extremely tightly. The
corrected C++ contact pass instead guards *only* interior joints 1, 2,
and 3 next to each mantle-arm root with progressive turn targets of
80, 100 and 120 degrees respectively. Joints 4 onward have no added
hard angle barrier. The root-cone allowance in the very soft tissue
profile is reduced from 165 to 105 degrees; the baseline profile
retains its existing 65-degree bound. These are provisional gameplay
limits, not measured octopus anatomy or guarantees of exact angles.
The projection is compliant/incremental and may require tuning under
large contact loads; the change is not yet build- or play-verified.


## Space-held suction control (2026-11-15)

**Current gameplay rule (supersedes the earlier Space-to-release descriptions):**
- Space **not held**: suction OFF across all eight arms, even while the
  user is pressing arm movement keys. Existing grips are released immediately;
  ordinary geometric contact and friction still apply.
- Space **held**: suction ON for all arms, including uncommanded/idle arms.
  A sucker only attaches when it actually meets the existing contact,
  orientation, and dwell requirements. Holding Space is permission to grip,
  not an unconditional weld or remote attachment.
- Space does **not** stop or override muscle commands. Arm keys, Shift, Ctrl
  and Space can be held together. Timed stroke-release phases may still peel
  their own sucker contacts when contraction demands it.
- The `step2` protocol's final bit now denotes `suction_enabled`, not
  `release_all`. The historical `PhysicsWorld::release_all_suckers`
  native API is retained for legacy tests, while `set_suction_enabled`
  provides the new per-frame gameplay gate.
- Native legacy `step` protocol and physics fixtures without an explicit
  Space gate preserve their previous automatic-suction semantics.

Regression coverage: Godot key serialization, bridge protocol OFF transition,
and native OFF / idle ON / immediate OFF sucker gates. These tests are
committed but not executed in the current environment.


## Passive soft-arm contour and rear root relaxation (2026-11-15)

Previously, the idle sweep motor pulled each mid/distal particle toward a
straight radial line; `demo.gd` also set idle curvature to zero.
That deterministic straightening overrode most passive deformation despite
soft XPBD material settings.

In grounded gameplay the idle radial motor no longer runs. Instead, a
weak, mirror-symmetric, nonuniform *passive curvature* target acts only
beyond 26% of arm length, ramping in gradually to keep the root smooth.
Bending and director constraints share the same target, while creep,
gravity and collisions remain active. This is a weak physics-rest-shape
bias, **not** a visual-only sinusoidal animation or a fixed skeleton pose.
Non-grounded fixtures retain their original operation.

The two rear-arm socket attraction gains/caps have been substantially
reduced so that mantle recline does not forcibly pull their proximal
rods into a sharp forward crease. The previously added proximal bend
safeguards remain in place; distal segments remain able to fold or coil.

This is a code-level correction, **not a verified rendered result**.
After building, check a no-input 300-tick grounded settle, rear mantle
lean and proximal arm angles, idle tip variance under perturbation,
suction-off behaviour and GameReady GLB mesh skin contact.


## Reach → seal → strong pull → release (2026-11-15)

This section **supersedes** all earlier `shorten → anchor → elongate`
or `reach → pull` descriptions.

- **Reach (0.18s)**: axial length 1.38, active shaping.
- **Seal (up to 0.40s)**: hold an extended arm near the contacted surface.
  When Space is held, proceed only after a real sucker attachment has been
  reported by the native world. No remote/fabricated contact is allowed.
- **Pull (0.42s maximum)**: axial contraction target 0.67 on
  *body-to-first-real-sucker* sections, with distal tissue beyond the
  planted sucker kept near neutral rest length. During this phase the
  native XPBD sucker compliance and break threshold are reinforced; a
  small centerline radius can no longer erase most available contact
  force. Lost grip terminates the pull. When Space is not held, a weaker
  friction-only shortening attempt uses extension 0.80; no suction is
  silently enabled.
- **Release (0.16s)**: muscle relaxes to extension 1.04. Suction ON is
  still controlled exclusively by Space, but the release phase
  deliberately detaches its old stroke contact so the next reach can
  place a new foothold. Unpressed arms may grip while Space is held.

**Contact topology:** the physical web was previously modeled only
with distance strands. New grounded-world one-sided contacts act between
deforming triangles spanning adjoining proximal arms (including a fan
to the central compliant socket) and the dorsal mantle ring. Near-root
arm capsules are also checked against upper mantle shell particles.
The root-most physically attached sections remain exempt from
self-separation, avoiding a hard disconnected hinge. This is a
coarse deformable collision approximation, not a watertight
continuous-triangle collision system or a new GPU cloth mesh.

**Status:** changes and controller tests are committed, but there is
no measured increase in per-stroke body travel and no on-screen proof
that flipping has stopped. Required: compile, run all regression
fixtures, and inspect GameReady skin under sustained suction while
a root is pulled into the torso.


## Controlled-arm-only suction and hard mantle/web angle limit

**Current gameplay rule (supersedes earlier global-Space grip behavior):**
Space held permits suction only on arms receiving an active muscle
command (activation > 0.50). All other arms remain nonadhesive even if
they touch the seabed. Space released disables all suction, as before.
Moving arms can still extend, seal, pull, release and retry. The native
legacy suction tests remain backwards compatible when an explicit
per-frame Space gate has not been installed.

For the grounded player model, the mantle's dorsal-to-ventral axis is
constrained to a maximum **65-degree tilt relative to the deformable
proximal arm web normal**, measured from arm nodes 0/2/4/6 at rod section
2. A mass-weighted position-level projection enforces this cone in
each solver contact iteration; it is not a camera transform correction
or a soft restoring torque. The arm-root radial direction cone was
also tightened to **85 degrees** for the very soft grounded profile.
The first three rod joints retain their progressive 80/100/120-degree
turn guards; distal joints have no additional angular clamp.

These are provisional game stability parameters. The web is a
deformable collision approximation, and the model still requires
Godot visualization plus native test runs to establish that neither
body inversion nor skin self-intersection occurs in all scenarios.


## Object grabbing and camera zoom (2026-11-15)

Gameplay mapping supersedes all earlier Shift-reach and Ctrl-brace actions:

- **Shift + an arm key:** command that arm to seek and grab the nearest
  **external C++-simulated object** (dynamic box or other octopus tissue).
  A contact joint forms only after the physical envelopes meet. Within a
  bounded one-metre search range, a force-limited motor approaches the
  closest candidate; it cannot remotely weld a target. A successful
  grab persists even after Shift is released, until Ctrl releases it
  or its physical load threshold breaks it.
- **Ctrl + arm key:** release that arm's object grab. **Ctrl alone:**
  release all object grabs on the selected octopus. Ctrl takes priority
  over Shift if both are held. Other octopuses are not affected.
- **Space:** remains the separate, held-only floor/prop sucker adhesion
  toggle for commanded arms. Object grabs are independent of Space.
- **Mouse wheel up/down:** multiply orbit-camera distance by 0.88
  or 1/0.88, clamped to 1.7–30 world metres; right drag still orbits.

The native step2 per-arm attachment slot is now a gameplay opcode:
0=keep, 1=request nearest-external grab, 2=release. The legacy step
attachment bit retains its original semantics. MuscleCommand.grab_mode
carries the parsed opcode. An attached tip transmits bilateral XPBD
reactions to a contacted object or other octopus. Only simulated bodies
can be selected; a separate character type requires registration into
the shared C++ physics world.

Regressions added for keyboard opcode serialization, Ctrl-only release,
invalid native opcodes and stable approach/release. **Not yet executed:**
native build/CTest, Godot input tests, visual mesh contact, force
calibration and physically verified grab persistence.


## Mouse-picked target, proximal hold and wrapping attack (2026-11-15)

This section replaces the previous **nearest-any-object** grab rule.

1. **Left click** an exposed dynamic prop or *another* octopus to select
   that exact target entity. A gold emissive target beacon floats above
   it and follows the moving object's center. The originally clicked
   world-space hit point is translated with the object's center so
   native targeting follows moving targets. Clicking empty space clears
   the selection. The currently controlled octopus is excluded.
2. **Shift + arm key** launches that arm at the *selected* entity only.
   A newly introduced backward-compatible **step3** command carries
   explicit entity kind/index and clicked hit point through the Godot
   to C++ boundary. The physics solver chooses the native target mass
   closest to the marked hit *within that selected entity*, rather
   than another nearby object. This is a coarse particle-based target
   approximation; it is not precise rendered-triangle contact.
3. The attack approach caps its translational drive at **52 N** with
   a **90 N/m** attraction, exactly twice the previous strong grab
   reach motor's 26 N / 45 N/m parameters. This does not claim measured
   speed or impact impulse is precisely doubled.
4. The grasp contact is now at arm **segment 13 of 16**, three
   segments inward from the extreme tip. Only once contact clearance
   is within 0.035 m is a bilateral XPBD joint acquired.
   Remaining distal nodes 14–16 receive bounded compliant forces to
   coil up to 1.7 radians around the actual contacted particle, with
   opposite reactions on the target mass. This is not a rigid or
   guaranteed complete wrap, and is not an independently simulated
   sucker-array grasp.
5. Shift can be released after a successful grasp; **Ctrl + arm**
   detaches the chosen grip and **Ctrl alone** clears selected animal
   grips. Space controls the separate suction system.
6. The original **left-drag force** gesture is now **Alt + left drag**
   to avoid accidental dragging while clicking to select targets.
   Right-drag orbit and mouse-wheel camera zoom are unchanged.

No new character body was invented. Non-octopus characters will be
selectable only after being registered in the native shared collision
world and exposed in a render snapshot.

Regression scripts were updated for the step3 wire suffix, active
target selection, the new object-grab contact index and Alt-drag.
**No local Godot/C++ binary run was possible in this environment;**
screen correctness, actual per-strike displacement, adhesion against
moving objects, and wrapping fidelity remain unverified.


## Grab lock state and grayscale arm controls (2026-11-15)

After a physical object grab succeeds (as opposed to an uncompleted
Shift reach), each per-arm native snapshot exports `grabbed=true`.
That exact state drives the arm's floating 3D key text:

- **GRABBED:** key text turns gray (#777777) and the HUD reports
  `<key>:GRAB LOCKED`. This uses the real native joint state, not
  the locally held Shift key or a predicted target hit.
- **LOCKED controls:** normal muscle stroke, active sweep, twist,
  sucker and repeated attack commands for that arm are ignored while
  the object grab joint is intact. C++ rejects changes to its motor
  targets even if a client sends them directly. The engine relaxes the
  attack motor to neutral at the moment of contact; passive soft-body
  motion and the physical object hold/wrapping contact continue.
- **RELEASE:** Ctrl + that arm key (or Ctrl alone for all arms of the
  selected octopus) clears the grab joint; controls and normal
  yellow/resting text resume on the following native snapshot.
- If a physically overloaded grab breaks by itself, controls become
  available again when the native `grabbed=false` snapshot arrives.

Render snapshots, the step3 bridge, player input, synthetic Godot
key checks, and bridge regression expectations were updated. These
are source changes without a verified Godot/C++ execution in the
current environment.

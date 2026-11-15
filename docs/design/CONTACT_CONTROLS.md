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

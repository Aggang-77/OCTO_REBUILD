# Twenty-percent tissue and web checkpoint

Gameplay reset uses `tissue_stiffness_ratio=.2`. Flesh edge, bend, shear and
torsion compliance is five times its prior value; muscle and upright forces
are multiplied by .2. Material volume constraints are softened too, while
rigid props and unilateral contact barriers keep their strength. The internal
cage volume compliance retains its existing square-root softness rule, so
this is a tissue stiffness profile, not an exact 80% reduction of every term.
`config()` returns requested settings so reset cannot compound the ratio.

Inactive proximal three joints no longer impose straight bending/director
targets. The second node's mantle tether is removed at this softness; rear
root shell tethers have additional sliding compliance. The 65-degree cone
is widened to 165 degrees. Calibrated, bounded connective-tissue forces
follow mantle lean and load rear sockets toward the sides/anterior; all
forces have opposite root/body reactions. This is an artistic rest-tension
model, not a validated anatomical constitutive law.

Neighboring proximal arm nodes share soft native web strands. The visible
web is a two-sided scalloped triangle fan following those native nodes.
It has no independent interior mass or triangle-surface collision, and its
plain material does not yet match the original texture perfectly.

Floor investigation found real skinned-geometry errors despite passing
centerline tests: GPU skin baking at tick 240 found -0.129475 m minimum Y.
Headless skin baking lacks registered GPU skin data and is skipped.
Floor support now includes compression bulge and a conservative .18 m
folding-skin envelope in this profile. The same final two-animal GPU scene
at tick 600 had minimum baked Y +0.102418 m, excluding shader displacement,
and ran at 59.73 simulation ticks/s, frame p95 8.33 ms. Screenshot:
`soft_web_floor.png`. This removes clipping in that measured pose at the
cost of visible excess clearance. Smaller .12/.16 m envelopes failed the
passive rear-fold regression; exact skin-matching floor contact is still OPEN.

Native regression at .2: 600-tick force-driven rear arm remained finite and
reached 0.4077 m forward; an independent 600-tick idle fixture folded rear
proximal nodes to +0.0922/+0.0988 m along the body's forward axis. This
supports the tested idle setup, not all collisions or input sequences.
Final Release CTest in `build/release-soft-web`: 8/8 PASS after restoring
the verified .18 profile.

Windows prevented overwriting the old release-final server (LNK1104).
The launcher selects the newest of the two known release-final/release-soft-web
server outputs, allowing a freshly verified process without killing an old
running demo. Old demo windows retain their original native world.

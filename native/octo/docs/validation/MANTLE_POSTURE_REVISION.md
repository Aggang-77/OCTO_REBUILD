# Mantle posture revision, 2026-11-15

Corrected the visible shrink path: independently clamped torso scales now
have determinant one, the procedural breathing scale is disabled, and local
shell displacements are capped at 0.045 model units instead of 0.12. These
render controls bound visual shrink; they do not prove exact skinned volume.

Grounded native physics gives the upper shell a 7 cm rearward rest offset
and increases each upper-shell mass from 10 g to 25 g, creating a gravity
lever arm. These are artistic engineering parameters, not measured anatomy.
The first arm segment has a 65 degree cone limit around its body-relative
outward direction. Positional corrections are distributed by inverse mass
between its two endpoints. This geometric limit is separate from XPBD
compliance and is not a complete angular joint with torso torque reaction.

Original-model shader calibration raises the Eye/Eyelid/Iris/Pupil assembly
by 0.065 model units and shears the upper hood rearwards by up to 0.10 model
units. The eye assembly adjustment is visual; it is not a physical eye joint.

Release CTest 8/8 passed before adding the stronger posture assertions;
the rebuilt contact/mantle test then passed those assertions with:
maximum root angle 65.0 degrees, resting upper-minus-lower shell Z -0.1775 m,
maximum loaded local chamber-volume error 0.0131.
GPU original-model two-animal scene, 240 ticks: exit 0, 59.98 simulation
ticks/s, frame interval p95 8.33 ms, no shader errors. Screenshot inspected:
`mantle_posture_revision.png`.

Remaining visual discrepancy: narrow radial arms and coarse junction/mantle
shape still do not reproduce the rounded thick junction in the user image.
Eye skin seams, dynamic skin clearance and exact visible volume are not
quantitatively validated. Do not describe this as a finished water balloon.

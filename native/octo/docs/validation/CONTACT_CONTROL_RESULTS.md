# Contact-control validation, 2026-11-15

Implementation: `game/scripts/arm_controls.gd`, Godot key dispatch and native
sucker acquisition/peeling. Read `docs/design/CONTACT_CONTROLS.md` for keys.

Release build `build/release-controls`: CTest 11/11 PASS, including eight
unique physical arm keys through `Input.parse_input_event`, simultaneous
front-arm input, Shift/Space priority, contact-gated state transitions,
simulation-clock reset, real native floor gripping and subsequent peeling.
The native grip fixture acquired six grips and had zero after releasing.

Original GameReady GPU scene with synthetic Up arrow (real event dispatch),
two animals and three dynamic props: 360 ticks, exit 0, all four phases
observed, peak 18 grips, selected body's displacement relative to tick 10
(0.261, -0.018, 0.443) m. Native clock 59.43 ticks/s, frame interval p95
8.33 ms. Input was released 45 ticks before the end. Screenshot inspected:
`contact_controls_crawl.png`. Baked skin minimum +0.0896 m excludes shader
offsets; the previously documented excess floor clearance still exists.

One earlier GPU 600-tick run also acquired 14 grips and moved +0.343 m in Z,
with -0.205 m lateral drift. A later headless CTest crawl took 29.95 seconds
for 600 ticks (20 sim ticks/s), despite ~2.34 ms native solve time. The
previously documented bridge timing variability is not resolved by controls.
Do not present this as a universal 60 Hz gate or a calibrated straight gait.

Pulling is conditional on native attachment, not an invented grip. Arrow
keys select muscles in staggered groups without applying body velocity or
coordinates. Controller timing uses native simulation time. The automatic
gait is an artistic assist, not measured biological octopus locomotion.
Sideways/backwards travel, precise heading and arbitrary object grasping
need further play calibration. Existing collision/skin proxy limitations
continue to apply.

Historical standalone input coverage now follows the current eight-key
controller. Its old breathing assertions were stale after the preceding
posture change; they now check the already-established determinant-one
torso scale and lack of artificial breathing.

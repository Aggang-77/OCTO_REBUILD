# Contract v1 — 2026-11-14

`include/octo/world.hpp` is the sole public API, owned by Astra. C++20, double SI,
right-handed coordinates, +Y up, gravity (0,-9.81,0), floor y=0. Animals have stable
indices, exactly eight arms. Arm 0 points +Z and angles increase toward +X.
Initial arm length should fit GameReady after documented uniform scaling, about
0.9m from a 0.2m root ring. 24 segments by default since the soft-arm slice; resolution changes must be reported.

One world owns body cage, rods, dynamic props, contacts and attachments. A step is
1/60 s and internally uses four 1/240 s substeps, eight solver sweeps initially.
Lambda resets at each substep; compliance is scaled with actual substep h*h.
Index lifetime lasts until reset. Calls use one thread. Snapshot owns its copies.
Invalid IDs and NaN inputs return false without mutation. Failed step is reported.
Muscle targets persist until replaced and are filtered. Drag is a capped spring
force; attachment is a bounded constraint with reaction on both participants.
Adjacent segments are excluded from self-contact; remote arms and different animals collide.
Tangential friction is bounded by normal reaction. All parameters are ASSUMED engineering values. Since the organic-hydrostat slice,
`WorldConfig::organic_profile` selects the broad-midarm section shape by default
(legacy cone optional); `idle_wriggle` controls distributed 3D bend and normalized
positive longitudinal rest-length waves. The scalar ellipse cross-section is
reconstructed to preserve nominal per-section area×length. These remain rod
proxies, not independently tessellated transverse tissue or exact surface CCD.

## Renderer transport

Initial deliverable uses a separate native stdio process, because no godot-cpp
dependency is installed. This is an explicit provisional bridge, not GDExtension completion.
Terra owns a versioned newline protocol accepting reset, full muscle commands, drag,
step and snapshot, and JSON output. One request in flight, nonblocking reads,
bounded read/backlog and child cleanup. Commands may be batched into one line.
Output is only authoritative C++ snapshot state. Render interpolation does not
alter simulation. Keep timing for physics, transfer/serialization and frame CPU
separate. No Godot dynamic physics is allowed. Standard 1/2/5/10 scenarios required.

## Physical fidelity boundary

XPBD positional constraints are the first vertical slice. Orientation-based
Cosserat shear/bending/twist, full anisotropic section contact and anatomical
mantle are separate gates. A transported visual frame is not independent
rotational dynamics. Radius derived from pi*a*b*L is not itself a pressure solve.
All such limitations must be labelled in implementation handoff and reports.

## Source analysis

Old project: b599085216a55a7665b73acb9858856db023d4ee, branch
feature/P2V-jelly-shared-world, heavily dirty. Existing Newton/FEM active-input
p95 reported 254.65ms (12 elements), 145.20ms (6 elements). Old issue 008 records
missing transverse cages, approximate skin tracking, missing chamber and performance.
Issue 005 records CCD/rest normal cycling. Rebuild does not reuse solver or claim
binary-state regression compatibility. Adapt the physical scenario and test it anew.
Original 15,203,672 byte GameReady GLB, 193 joints and embedded material are reused locally.

Sources checked: https://mmacklin.com/xpbd.pdf (XPBD compliance/substep scaling),
https://animation.rwth-aachen.de/publication/0550/ (position/orientation rods).
These papers justify the method family, not our unmeasured fidelity or runtime.

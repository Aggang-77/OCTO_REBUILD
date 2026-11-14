# Organic hydrostat silhouette and traveling longitudinal contraction

## Root cause
The original demo set rest radius to `r(u)=0.036*(1-0.8*u)` and reapplied that same straight taper in the Godot bone-scaling reference. Increasing the 16/24-segment count alone could not fix a tapered, needle-like mesh.

## Implementation
- New organic rest profile `r(u)=0.009+0.039*sqrt(max(0,1-u^5))` metres, where `u` is normalized arc length. Broad middle and rounded distal taper. `organic_profile=true` by default and selectable legacy profile for A/B comparison.
- C++ XPBD receives a continuous traveling curvature muscle target in 3D and an additional per-segment longitudinal strain wave. Each section's positive raw length is `exp(0.34*idle*sin(phase+0.5))`; targets are normalized to sum to `0.9*active.extension` metres.
- The snapshot's section ellipse obeys `r_x*r_y*L=r0(u)^2*L0` for each rod segment; local contact flattening preserves area using reciprocal axes. Radial particle proxies follow this model approximately.
- Godot continues to skin the original GLB and materials, but compares solver cross sections with the *imported conical* profile; radial scale range expanded from 0.5..1.8 to 0.4..4 to allow thicker organic midarms.
- Existing controls are unchanged. `--legacy-profile` or PowerShell `-LegacyProfile` restores the original radius profile. Protocol optional arguments: `reset ANIMALS [SPACING [IDLE [SEGMENTS [ORGANIC(0/1)]]]]`.

## Validation and limits
- Native physics regression: plump-midarm geometric ratio, changing radius under traveling muscle load, per-section volume reconstruction identity and nonfinite checks.
- Wire test: optional profile parameter, legacy resolution and invalid profile rejection.
- Full volumetric tissue/FEM or a high-resolution deforming surface is NOT present: collisions use particle spheres, so exact deforming skin-to-skin collisions and physical surface normals are unsolved. Skinning can produce seams or creases, particularly around suckers. The original GLB is not included in git.
- CI must distinguish Linux/Windows native results from real Godot GPU, manual appearance, and worst-case ten-animal 60 FPS. Tuning values are art direction, not experimentally derived octopus constitutive parameters.

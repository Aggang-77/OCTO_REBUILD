# Interbrachial webs and thick visual jelly tentacles

## Implementation

The original visual sleeve multiplier was 1.15× the C++ physical
section radius. This slice uses `1.50*(1+0.16*(1-u)^2)`, so the
default proximal arm is ~1.74× the physical rod radius and the
distal arm is ~1.50×. The mesh is still derived at each physics tick
from the authoritative C++ XPBD arm nodes/radii.

There are eight web panels per animal: arm `k` to `(k+1)%8`.
Each web has a 17-row × 13-column cross-arm grid, double thickness
surfaces, and a stitched perimeter. Its bounds are sampled from
the current physical arm centerlines, attaching at the outside of
the thickened jelly sleeve. Its distal edge is concave, extending
48% of arm length at each arm boundary, 24% at the midpoint.
The interior sags toward the floor based on arm separation. The
vertex shader uses slower waves than the arm skin and zeroes
displacement at each seam so the moving attachment remains stable.

## Verification

The Godot 4.6.2 GitHub Actions OpenGL/Xvfb test renders a real
screenshot and checks eight closed, subdivided web meshes per
octopus, with at least 400 vertices and 400 triangles in the
checked panel. Logs and PNG are included in `jelly-preview-linux`
artifacts. The original imported GameReady GLB was not included
in Git and its integration remains subject to manual inspection.

## Physics and performance limitations

Webs and thickness are strictly **visual**; their vertices are not
C++ collision primitives or connected by physical tension. A
rigid object can intersect the web. Extremely tangled arms may
produce visible overlaps; exact octopus web dynamics would require
membrane/cloth/volume constraints and corresponding collision
handling in the shared C++ world. The denser visual mesh also
adds skin rebuild cost. Ten-animal real-time performance is not
validated; for >2 animals jelly is disabled by default unless
explicitly enabled.

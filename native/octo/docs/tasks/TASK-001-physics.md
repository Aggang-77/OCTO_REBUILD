# S01 — unified XPBD first vertical slice

Owner Sol, branch feat/xpbd-world, worktree OCTO_REBUILD_SOL, base cf42649.
Allowed core/**, tests/physics_tests.cpp, docs/tasks/S01_HANDOFF.md only.
Public include/octo/world.hpp and CMake owned by Astra. API contract v1.
Build with tools/build.ps1 once source exists. Native dependency C++20/MSVC only.
Implement gravity, 8 independently commanded arms, deformable body cage, floor
and pair contact/friction, dynamic props and bilateral reactions, bounded force
drag, finite-strength representative attachments where possible.
Reject unsupported nonzero physical twist; tangent frames are render data only.
Initial engineering material values are ASSUMED. No biological validation claim.

Required tests: analytical free fall without external damping/contact;
internal momentum balance with gravity/damping off; finite values and contact;
commands only change targets until stepping; rejected invalid input; active arm
response; volume diagnostics include actual torso tetra geometry.
Report actual commands, output, commit, PASS/FAIL/PARTIAL/NOT TESTED and known limits.

# OCTO rebuild

The adjacent OCTO checkout is read-only historical reference. Preserve all of it.
This is a new independent repository. Astra owns public contracts, CMake, integration, docs and gates.
Sol owns core/ and tests/physics_tests.cpp. Terra owns bridge/, game/, tools/run* and tools/godot*.
Each implementation uses its own branch/worktree. Do not change another owner's files.
All physics uses SI units, Y up, fixed 1/60 s stepping, one C++ world.
User input changes muscle targets or bounded forces, never state coordinates.
Claims require actual build/test/run evidence. Performance is separate from physical completeness.
Read docs/reference specifications and docs/architecture/API_CONTRACTS.md.

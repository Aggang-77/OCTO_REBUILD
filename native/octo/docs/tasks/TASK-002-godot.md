# T01 — original art and authoritative native live demo

Owner Terra, branch feat/godot-demo, worktree OCTO_REBUILD_TERRA, base cf42649.
Allowed bridge/**, game/**, tools/run*, tools/godot*, docs/tasks/T01_HANDOFF.md.
No edits to core/public API/CMake. Godot 4.6.2, provisional stdio transport.
Implement protocol v1, eight independent keys, animal selection, force drag,
reset and cleanup. Only C++ world determines motion. Use original GameReady GLB
and embedded PBR materials, map actual snapshot bones and radii, label skin limits.
Validate Godot import/parser/headless loop and actual GPU screenshot after integration.
Provide 1/2/5/10 run arguments, per-frame/RPC metrics, source path/checksum.
No GDExtension completion claim while it is a child-process bridge.

Protocol: `1 ID reset ANIMALS`, `1 ID snapshot`, `1 ID quit`;
`1 ID step N` + N records `animal arm activation curvature extension twist stiffness attach`
+ drag record `kind index arm x y z stiffness max_force`.
Response: newline JSON `version,id,ok,snapshot|error`; one request in flight.

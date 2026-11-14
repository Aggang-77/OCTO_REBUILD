extends SceneTree
## Run once after importing assets; saves real editor-visible geometry and collision.

func _initialize() -> void:
	_build.call_deferred()

func _own(node: Node, scene_root: Node) -> void:
	for child in node.get_children():
		child.owner = scene_root
		_own(child, scene_root)

func _build() -> void:
	DirAccess.make_dir_recursive_absolute("res://assets/environment/generated")
	var arena := TidalArena.new()
	arena.name = "TidalColosseum"
	root.add_child(arena)
	arena.build_map()
	_own(arena, arena)
	var scene := PackedScene.new()
	var error := scene.pack(arena)
	if error == OK:
		error = ResourceSaver.save(scene, "res://scenes/tidal_colosseum_environment.tscn")
	if error != OK:
		printerr("Map bake failed: ", error)
		quit(1)
		return
	print("TIDAL_MAP_BAKED: ", arena.find_children("*", "RigidBody3D", true, false).size(), " physics props; editor-visible ruins, mudflat, water and imported assets.")
	quit(0)

extends SceneTree
var checks: int=0
var failures: Array[String]=[]
func _initialize() -> void:_run.call_deferred()
func ticks(count: int) -> void:
	for i in range(count):await physics_frame
func check(condition: bool, message: String) -> void:
	checks+=1
	if condition:print("PASS: ",message)
	else:failures.append(message);printerr("FAIL: ",message)
func _run() -> void:
	var lab: Node3D=load("res://scenes/tidal_hunter_lab.tscn").instantiate()
	root.add_child(lab);current_scene=lab
	await ticks(25)
	check(lab.arena.props.size()==48,"Existing map still loads its props and character lab")
	var event:=InputEventKey.new();event.keycode=KEY_F10;event.pressed=true
	lab._unhandled_input(event)
	await process_frame
	await ticks(25)
	check(current_scene.scene_file_path=="res://scenes/hunter_fight_lab.tscn","F10 opens the playable fight mode from the existing map")
	check(is_instance_valid(current_scene.player.fighter.boxes) and current_scene.player.fighter.control==&"player","The entered fight mode has ready manual controls and body boxes")
	current_scene._unhandled_input(event)
	await process_frame
	await ticks(25)
	check(current_scene.scene_file_path=="res://scenes/tidal_hunter_lab.tscn" and not paused,"F10 returns to the map and AI lab without a paused scene")
	print("FIGHT_NAV_TEST_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)

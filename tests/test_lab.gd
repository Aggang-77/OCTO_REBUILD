extends SceneTree
var failures: Array[String] = []
var checks: int = 0
var lab: Node3D

func _initialize() -> void:
	_run.call_deferred()

func check(value: bool, message: String) -> void:
	checks+=1
	if value: print("PASS: ",message)
	else:
		failures.append(message)
		printerr("FAIL: ",message)

func ticks(count: int) -> void:
	for i in range(count):await physics_frame

func _run() -> void:
	lab=load("res://scenes/hunter_lab.tscn").instantiate()
	root.add_child(lab)
	current_scene=lab
	await ticks(12)
	check(lab._character_picker.item_count==HunterAnimation.CHARACTERS.size(),"Lab exposes every supplied character choice")
	for index in range(3):
		lab._select_character(index)
		await ticks(12)
		check(lab.hunter.character_index==index and not lab.threat.active and lab.hunter.state==&"idle","Character %d selection starts a clean idle simulation" % index)
	lab._set_level(3)
	check(lab.hunter.animation.weapon.visible,"Level 3 displays the hand-held sword")
	lab._strong_capture.button_pressed=false
	lab._capture_target()
	await ticks(20)
	check(lab._capture_preview._hold_blend>0.9 and lab._capture_preview.tube_mesh.get_surface_count()>0,"Capture control visibly wraps a tentacle around the target")
	await ticks(140)
	check(not is_instance_valid(lab.hunter.capture_source),"Normal capture control allows the elbow breakaway")
	lab._strong_capture.button_pressed=true
	lab._capture_target()
	await ticks(130)
	check(is_instance_valid(lab.hunter.capture_source),"Strong capture control keeps the target restrained after an elbow")
	lab.hunter.release_capture()
	await ticks(30)
	check(lab._capture_preview._hold_blend<0.01,"Release removes the tentacle wrap")
	lab._release_all()
	lab._set_level(3)
	lab._grab_arm(&"right_forearm")
	check(lab.hunter.physics_rig.grips.size()==1,"Arm control creates a real part-specific physical grip")
	lab._physics_demo.set_mass(20.0)
	check(lab.threat.physics_anchor.mass==20.0,"Tentacle mass control changes the actual rigid-body mass")
	lab._attempt_physical_slash()
	check(lab.hunter.state==&"slash","Arm restraint permits a sword effort instead of disabling the action")
	await ticks(35)
	var mobility: float=lab.hunter.physics_rig.get_mobility(&"right_forearm")
	check(mobility>0.0 and mobility<1.0,"Physical grip produces a continuous arm mobility value")
	lab._release_all()
	check(lab.hunter.physics_rig.grips.is_empty(),"Release control clears every physical grip")
	var key:=InputEventKey.new()
	key.keycode=KEY_SPACE
	key.pressed=true
	lab._unhandled_input(key)
	var paused_position: Vector3=lab.hunter.physics_rig.get_part_position(&"pelvis")
	for i in range(10):await process_frame
	check(lab.hunter.physics_rig.get_part_position(&"pelvis").distance_to(paused_position)<0.00001,"Pause stops rigid-body simulation as well as AI")
	lab._unhandled_input(key)
	print("LAB_TEST_RESULT ",JSON.stringify({"checks":checks,"failures":failures,"passed":failures.is_empty()}))
	quit(0 if failures.is_empty() else 1)

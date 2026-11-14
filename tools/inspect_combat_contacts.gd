extends SceneTree
var lab: Node3D
var actor: HunterTarget
var rival: HunterTarget
var history: Array[Dictionary]=[]
var tracking: bool=false
var move: StringName

func _initialize() -> void:_run.call_deferred()
func ticks(count: int) -> void:
	for i in range(count):await physics_frame
func sample() -> void:
	if not tracking:return
	var foot: Area3D=actor.fighter.boxes.hitboxes[&"right_foot"]["area"]
	var head: Area3D=rival.fighter.boxes.hurtboxes[&"head"]["area"]
	var torso: Area3D=rival.fighter.boxes.hurtboxes[&"torso"]["area"]
	history.append({"move":move,"time":actor.fighter.elapsed*actor.fighter.rate,"foot":foot.global_position,"head":head.global_position,"torso":torso.global_position,"active":not actor.fighter.active_windows().is_empty()})
func _run() -> void:
	lab=load("res://scenes/hunter_fight_lab.tscn").instantiate();root.add_child(lab);current_scene=lab
	actor=lab.player;rival=lab.rival;lab._ai_toggle.button_pressed=false
	await ticks(40)
	actor.animation.skeleton.skeleton_updated.connect(sample)
	for kind in [&"kick_a",&"kick_d"]:
		lab.reset_fight();rival.fighter.control=&"dummy"
		actor.global_position=Vector3(0,0,0.375);rival.global_position=Vector3(0,0,-0.375)
		actor.visual.rotation.y=PI;rival.visual.rotation.y=0
		actor.physics_rig.reset_pose();rival.physics_rig.reset_pose()
		await ticks(15)
		move=kind;history.clear();tracking=true
		actor.fighter.request_move(kind)
		await ticks(70)
		tracking=false
		var nearest:=INF;var best:Dictionary={}
		for entry in history:
			if entry["active"]:
				var distance:float=entry["foot"].distance_to(entry["head"])
				if distance<nearest:nearest=distance;best=entry
		print("KICK_PATH ",kind," nearest head ",nearest," best ",best)
		FileAccess.open("res://.tools/%s_path.json"%kind,FileAccess.WRITE).store_string(JSON.stringify(history,"  "))
	quit()

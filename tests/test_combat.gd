extends SceneTree
var lab: Node3D
var player: HunterTarget
var rival: HunterTarget
var failures: Array[String]=[]
var contacts: Array[Dictionary]=[]
var checks: int=0

func _initialize() -> void:_run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks+=1
	if condition:print("PASS: ",message)
	else:
		failures.append(message)
		printerr("FAIL: ",message)

func ticks(count: int) -> void:
	for i in range(count):await physics_frame

func fresh(distance: float=0.75) -> void:
	lab.reset_fight()
	lab._ai_toggle.button_pressed=false
	rival.fighter.control=&"dummy"
	player.global_position=Vector3(0,0,distance*0.5)
	rival.global_position=Vector3(0,0,-distance*0.5)
	player.visual.rotation.y=PI
	rival.visual.rotation.y=0.0
	player.physics_rig.reset_pose()
	rival.physics_rig.reset_pose()
	for box in rival.fighter.boxes.hurtboxes.values():box["area"].collision_layer=HunterCombatHitboxes.HURT_LAYER
	contacts.clear()

func key(code: int) -> void:
	var event:=InputEventKey.new()
	event.physical_keycode=code
	event.keycode=code
	event.pressed=true
	lab._unhandled_input(event)

func _run() -> void:
	lab=load("res://scenes/hunter_fight_lab.tscn").instantiate()
	root.add_child(lab)
	current_scene=lab
	player=lab.player
	rival=lab.rival
	lab._ai_toggle.button_pressed=false
	await ticks(45)
	player.fighter.strike_landed.connect(func(contact: Dictionary):contacts.append(contact))
	for index in range(3):
		player.set_character(index)
		await ticks(15)
		for clip in [&"punch_jab",&"punch_cross",&"punch_hook",&"punch_quad",&"kick_a",&"kick_b",&"kick_c",&"kick_d",&"knee",&"slide",&"hit_head_a",&"hit_body_a",&"combat_idle"]:
			check(player.animation._clips.has(clip),"Character %d has retargeted combat clip %s"%[index,clip])
		check(player.fighter.boxes.hurtboxes.size()==15 and player.fighter.boxes.hitboxes.size()==10,"Character %d has separate body hurtboxes and limb hitboxes"%index)
		check(not player.animation.weapon.visible,"Character %d fights without the sword"%index)
	player.set_character(0)
	await ticks(20)
	fresh(3.0)
	var start:=player.global_position
	Input.action_press("fight_forward")
	await ticks(32)
	Input.action_release("fight_forward")
	check(player.global_position.distance_to(start)>0.75,"WASD input physically moves the controlled character")
	Input.action_press("fight_back")
	await ticks(2)
	check(player.fighter.motion==&"turn" and player.state==&"turning","Reversing movement uses the turn animation")
	await ticks(40)
	Input.action_release("fight_back")
	check(player.visual.global_basis.z.z>0.5,"The turn ends facing the new movement direction")
	fresh(3.0)
	key(KEY_SPACE)
	await ticks(22)
	check(player.fighter.motion==&"slide","Space starts a slide rather than pausing the game")
	check(player.get_node("CollisionShape3D").shape.height<0.8,"Sliding lowers the physical controller shape")
	var skeleton:=player.animation.skeleton
	var head:=skeleton.global_transform*skeleton.get_bone_global_pose(skeleton.find_bone("Head")).origin
	check(head.y<1.05,"The actual sliding animation lowers the head and its hurtbox")
	await ticks(85)
	check(player.get_node("CollisionShape3D").shape.height>1.5,"The standing collision shape returns after sliding")
	fresh(4.0)
	player.fighter.camera=null
	player.global_position=Vector3(-4.4,0,1.3)
	player.visual.rotation.y=PI
	player.physics_rig.reset_pose()
	Input.action_press("fight_forward")
	await ticks(35)
	Input.action_release("fight_forward")
	check(player.global_position.z>0.25,"A standing fighter is blocked by the real low slide obstacle")
	player.reset_target(Vector3(-4.4,0,1.3))
	player.visual.rotation.y=PI
	player.fighter.request(&"slide")
	await ticks(75)
	check(player.global_position.z<-0.4,"A sliding fighter can pass underneath that same physical obstacle")
	player.fighter.camera=lab.camera
	fresh(4.0)
	player.fighter.request_move(&"punch_cross")
	await ticks(75)
	check(rival.objective.health==100.0 and contacts.is_empty(),"A punch with no hitbox contact causes no damage")
	fresh(0.60)
	await ticks(30)
	check(rival.objective.health==100.0,"Touching or standing close without an active attack causes no damage")
	# Interrupt an opponent's actual attack and observe the supplied hit clip,
	# rather than merely checking its HP or a reaction state label.
	fresh(0.75)
	await ticks(15)
	var before_head:=rival.animation.skeleton.get_bone_pose_rotation(rival.animation.skeleton.find_bone("Head"))
	var before_chest:=rival.animation.skeleton.get_bone_pose_rotation(rival.animation.skeleton.find_bone("Spine2"))
	rival.fighter.request_move(&"punch_cross")
	player.fighter.request_move(&"punch_jab")
	for i in range(50):
		await physics_frame
		if not contacts.is_empty():break
	check(not contacts.is_empty() and rival.fighter.motion==&"reaction","A struck opponent interrupts its current attack and begins a hit reaction")
	check(rival.fighter.last_reaction.begins_with("hit_") and rival.animation._action_node.animation==rival.animation._clips.get(rival.fighter.last_reaction),"The victim plays the supplied hit FBX clip")
	check(rival.fighter.active_windows().is_empty(),"An interrupted opponent's attack hitboxes immediately switch off")
	await ticks(9)
	var after_head:=rival.animation.skeleton.get_bone_pose_rotation(rival.animation.skeleton.find_bone("Head"))
	var after_chest:=rival.animation.skeleton.get_bone_pose_rotation(rival.animation.skeleton.find_bone("Spine2"))
	check(maxf(before_head.angle_to(after_head),before_chest.angle_to(after_chest))>0.05,"The victim's animated body visibly recoils after contact")
	for move in [&"punch_jab",&"punch_cross",&"punch_hook",&"kick_a",&"kick_b",&"kick_c",&"kick_d",&"knee",&"punch_quad"]:
		fresh(1.1 if move in [&"kick_a",&"kick_d"] else 0.75)
		await ticks(15)
		check(player.fighter.request_move(move),"Can start combat move %s"%move)
		await ticks(100)
		print("COMBAT_CONTACT ",move," HP ",rival.objective.health," count ",contacts.size()," parts ",contacts.map(func(c: Dictionary):return [c["attack_part"],c["hurt_part"],c["damage"]]))
		check(not contacts.is_empty() and rival.objective.health<100.0,"%s damages only through real limb/body shape contact"%move)
		check(contacts.size()<= (4 if move==&"punch_quad" else 1),"%s does not repeatedly damage the same victim within one strike"%move)
		if not contacts.is_empty():
			var contact:=contacts[0]
			check(contact.has("attack_part") and contact.has("hurt_part") and contact["attacker"]==player and contact["victim"]==rival,"Contact reports attack limb and struck body part separately")
	# Disable body hurtboxes to test a genuine head-only impact and its reaction.
	fresh(1.1)
	for part in rival.fighter.boxes.hurtboxes:
		if part!=&"head":rival.fighter.boxes.hurtboxes[part]["area"].collision_layer=0
	player.fighter.request_move(&"kick_a")
	await ticks(95)
	check(not contacts.is_empty() and contacts[0]["hurt_part"]==&"head","A high kick can contact the independent head hurtbox")
	check(rival.fighter.last_reaction.begins_with("hit_head"),"A head impact plays a head-hit motion before a heavy-hit knockdown")
	if not contacts.is_empty():check(contacts[0]["damage"]>23.0,"Head contact applies its body-part damage multiplier")
	# Verify the body cannot lose HP outside an enabled victim hurtbox.
	fresh(0.65)
	for box in rival.fighter.boxes.hurtboxes.values():box["area"].collision_layer=0
	player.fighter.request_move(&"punch_jab")
	await ticks(65)
	check(rival.objective.health==100.0 and contacts.is_empty(),"Disabling hurtboxes prevents damage even at close range")
	for index in [1,2]:
		player.set_character(index)
		await ticks(15)
		for move in [&"punch_jab",&"kick_c"]:
			fresh(0.75)
			await ticks(15)
			player.fighter.request_move(move)
			await ticks(85)
			check(not contacts.is_empty() and rival.objective.health<100.0,"Character %d can land %s using its own rig"%[index,move])
	player.set_character(0)
	await ticks(15)
	fresh(0.70)
	rival.objective.health=1.0
	player.fighter.request_move(&"punch_jab")
	await ticks(80)
	check(rival.incapacitated and rival.objective.health==0.0,"Actual strike damage can reduce an opponent to zero health")
	check(player.fighter.round_over and rival.fighter.round_over and not lab._result_label.text.is_empty(),"A knockout ends the sparring round")
	await ticks(250)
	check(rival.state==&"knocked_out" and rival.is_fallen(),"A knocked-out fighter stays down until reset")
	key(KEY_R)
	await ticks(10)
	check(rival.objective.health==100.0 and player.objective.health==100.0 and not player.fighter.round_over,"Reset restores health, state and the round")
	key(KEY_P)
	check(paused,"Pause is bound to P")
	key(KEY_P)
	check(not paused,"P resumes the fight")
	fresh(1.5)
	player.fighter.control=&"dummy"
	rival.fighter.control=&"sparring"
	await ticks(240)
	check(player.objective.health<100.0 and player.fighter.last_reaction.begins_with("hit_"),"Sparring AI can strike the player and trigger the player's supplied hit motion")
	player.fighter.control=&"player"
	var report:={"checks":checks,"failures":failures,"passed":failures.is_empty()}
	FileAccess.open("res://.tools/combat_test_results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
	print("COMBAT_TEST_RESULT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

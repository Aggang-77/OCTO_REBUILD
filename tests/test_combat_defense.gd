extends SceneTree
var lab
var p: HunterTarget
var r: HunterTarget
var contacts: Array[Dictionary]=[]
var checks: int=0
var failures: Array[String]=[]
func _initialize() -> void:run.call_deferred()
func check(value: bool, message: String) -> void:
 checks+=1
 if value:print("PASS: ",message)
 else:failures.append(message);printerr("FAIL: ",message)
func ticks(n: int) -> void:
 for i in n:await physics_frame
func fresh(d: float=0.65) -> void:
 lab.reset_fight();lab._ai_toggle.button_pressed=false
 p.fighter.control=&"dummy";r.fighter.control=&"dummy"
 p.fighter.opponent=r;r.fighter.opponent=p
 p.global_position=Vector3(0,0,d/2);r.global_position=Vector3(0,0,-d/2)
 p.visual.rotation.y=PI;r.visual.rotation.y=0.0
 p.physics_rig.reset_pose();r.physics_rig.reset_pose()
 for b in r.fighter.boxes.hurtboxes.values():b.area.collision_layer=64
 contacts.clear()
func key(code: int) -> void:
 var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=true
 lab._unhandled_input(event)
func windup(fighter: HunterFighter) -> int:
 var count:=0
 while fighter.active_windows().is_empty() and count<90:
  await physics_frame;count+=1
 return count
func shoulders() -> Vector3:
 var s:=p.animation.skeleton
 var right:=s.global_transform*s.get_bone_global_pose(s.find_bone("RightArm")).origin
 var left:=s.global_transform*s.get_bone_global_pose(s.find_bone("LeftArm")).origin
 return (p.visual.global_basis.inverse()*(right-left)).normalized()
func run() -> void:
 lab=load("res://scenes/hunter_fight_lab.tscn").instantiate();root.add_child(lab);current_scene=lab
 p=lab.player;r=lab.rival;lab._ai_toggle.button_pressed=false
 await ticks(30)
 p.fighter.strike_landed.connect(func(c: Dictionary):contacts.append(c))
 for index in range(3):
  p.set_character(index);await ticks(10)
  var all_present:=true
  for clip in ["parry","dodge","pivot","kick_front","kick_martelo","combo_knee_upper","celebrate","victory_pose","stunned"]:all_present=all_present and p.animation._clips.has(clip)
  check(all_present,"Character %d includes the new retargeted defense and victory motions"%index)
  fresh(4.0);await ticks(10)
  key(KEY_I);await ticks(1)
  check(p.fighter.move==HunterCombatMoves.SPECIALS[index],"I selects character %d's distinct special"%index)
  p.fighter.interrupt();p.animation.cancel_action();p.stamina=100
  key(KEY_K);await ticks(1)
  check(p.fighter.move==HunterCombatMoves.CHARACTER_KICKS[index][0],"K selects character %d's own kick repertoire"%index)
 p.set_character(0);await ticks(10)
 fresh(4.0);await ticks(10)
 p.fighter.request_move(&"punch_jab")
 var normal_windup:=await windup(p.fighter)
 await ticks(40)
 check(p.fighter.motion==&"","A jab quickly returns to movement after its active window")
 fresh();await ticks(15)
 r.fighter.request(&"parry");p.fighter.request_move(&"punch_jab")
 await ticks(45)
 check(r.objective.health==100.0 and not contacts.is_empty() and contacts[0].get("parried",false),"A timed, frontal limb contact is parried without damage")
 check(r.fighter.counter_left>0.0,"A successful parry awards a temporary counter windup bonus")
 check(p.fighter.motion==&"stagger" or p.state==&"parried" or p.fighter.motion==&"","Parrying stops the incoming attack")
 check(r.fighter.request_move(&"punch_jab"),"The defender can counter after the short parry action")
 var faster_windup:=await windup(r.fighter)
 print("COUNTER_TIMING normal=",normal_windup," counter=",faster_windup)
 check(faster_windup<normal_windup and faster_windup>=int(normal_windup*0.6),"A successful defense shortens the next attack windup")
 check(r.fighter.counter_left==0.0 and r.fighter.counter_attack,"The bonus is consumed by exactly one attack")
 await ticks(2)
 check(is_equal_approx(r.animation._action_speed,r.fighter.rate),"Impact playback returns to normal speed after the faster windup")
 fresh(4.0);r.fighter.request(&"parry");await ticks(40)
 check(r.fighter.counter_left==0.0,"An empty parry grants no counter bonus")
 fresh();await ticks(15)
 p.fighter.request_move(&"punch_jab");await ticks(22);r.fighter.request(&"parry");await ticks(25)
 check(r.objective.health<100.0 and r.fighter.counter_left==0.0,"A late parry does not undo a hit or award a bonus")
 fresh(4.0);r.fighter.request(&"dodge");await ticks(40)
 check(r.fighter.counter_left==0.0,"An empty dodge grants no counter bonus")
 fresh(0.75);await ticks(15)
 var before:=r.global_position
 r.fighter.request(&"dodge");p.fighter.request_move(&"punch_cross");await ticks(40)
 check(r.global_position.distance_to(before)>0.65,"Dodge moves the real controller away from the attack")
 check(r.objective.health==100.0 and r.fighter.counter_left>0.0,"Evading an actual incoming attack awards the counter bonus")
 check(r.fighter.boxes.dodge_trace.is_empty(),"Dodge threat snapshots disappear when the step ends")
 fresh(0.75);await ticks(15)
 p.fighter.request_move(&"punch_jab");r.fighter.request_move(&"punch_jab");await ticks(50)
 check(p.objective.health<100.0 and r.objective.health<100.0,"Nearly simultaneous physical strikes can damage both fighters")
 fresh(1.4);await ticks(15)
 p.fighter.request_move(&"punch_jab");await ticks(50)
 check(r.objective.health==100.0,"A distant punch cannot hit through a reach value")
 fresh(1.4);await ticks(15)
 p.fighter.request_move(&"kick_front");await ticks(70)
 check(r.objective.health<100.0 and not contacts.is_empty(),"A forward kick physically reaches beyond punching distance")
 fresh(0.75);await ticks(15)
 p.fighter.opponent=null
 r.global_position.x=0.55
 p.fighter.request_move(&"punch_jab");await ticks(50)
 check(r.objective.health==100.0,"A punch passing beside the body misses instead of using a broad sideways area")
 fresh();await ticks(15)
 p.fighter.request_move(&"elbow_strike");await ticks(50)
 check(contacts.size()==1 and "elbow" in String(contacts[0].attack_part),"A close elbow uses its own hitbox and hits once")
 fresh();await ticks(15)
 p.fighter.request_move(&"punch_jab")
 for i in 45:
  await physics_frame
  if r.fighter.motion==&"reaction":break
 check(r.fighter.motion==&"reaction" and not r.fighter.request_move(&"punch_jab"),"A real hit still imposes reaction stun")
 var reaction_frames:=0
 while r.fighter.motion==&"reaction" and reaction_frames<60:
  await physics_frame;reaction_frames+=1
 check(reaction_frames>=14 and reaction_frames<=24,"Body stun remains perceptible and ends in roughly 0.30 seconds")
 fresh(4.0);await ticks(15)
 r.fighter.request_move(&"punch_jab");await windup(r.fighter)
 r.fighter.receive_strike({"attacker":p,"hurt_part":&"head","damage":32.2,"position":r.fighter.boxes.hurtboxes.head.area.global_position},3.0)
 check(r.fighter.motion==&"attack","A heavy head impact still allows the short active-strike trade window")
 await ticks(28)
 check(r.is_fallen(),"The delayed heavy-hit reaction preserves its physical knockdown")
 p.set_character(1);await ticks(10)
 fresh();await ticks(15)
 key(KEY_I)
 for i in 25:
  await physics_frame
  if is_instance_valid(p.fighter.clinch_victim):break
 check(p.fighter.clinch_victim==r and r.physics_rig.grips.size()==2,"Face grab requires actual palm/head contact and creates two physical restraints")
 check(r.fighter.motion==&"clinched","The grabbed opponent responds to the clinch")
 await ticks(70)
 print("CLINCH_CONTACTS ",contacts.map(func(c: Dictionary):return [c.attack_part,c.hurt_part,c.damage]))
 check(r.objective.health<100.0 and contacts.size()==2 and contacts[1].attack_part==&"left_knee","A successful face grab follows with one damaging knee")
 check(r.physics_rig.grips.is_empty() and not is_instance_valid(p.fighter.clinch_victim),"Finishing the special releases both physical restraints")
 fresh(2.0);await ticks(15)
 key(KEY_I);await ticks(60)
 check(r.objective.health==100.0 and r.physics_rig.grips.is_empty() and p.fighter.motion==&"","A missed grab neither teleports the victim nor performs a free knee")
 p.set_character(2);await ticks(10)
 fresh();await ticks(15);key(KEY_I);await ticks(120)
 check(r.objective.health<80.0 and contacts.size()>=2,"The third character's knee/uppercut special can land multiple independent strikes")
 p.set_character(0);await ticks(10)
 fresh(4.0);p.fighter.control=&"player";p.fighter.camera=null
 await ticks(10)
 Input.action_press("fight_forward");await ticks(22)
 var initial_shoulders:=shoulders()
 Input.action_release("fight_forward");Input.action_press("fight_back")
 var total_yaw:=0.0
 var last_yaw:=p.visual.rotation.y
 var turns:=0
 var was_turn:=false
 var shoulder_drift:=0.0
 for i in 50:
  await physics_frame
  total_yaw+=absf(angle_difference(last_yaw,p.visual.rotation.y));last_yaw=p.visual.rotation.y
  if p.fighter.motion==&"turn":
   if not was_turn:turns+=1
   shoulder_drift=maxf(shoulder_drift,initial_shoulders.angle_to(shoulders()))
  was_turn=p.fighter.motion==&"turn"
 Input.action_release("fight_back")
 check(turns==1 and total_yaw<PI+0.18 and total_yaw>PI-0.18,"A movement reversal turns once through 180 degrees without overrotation")
 print("TURN shoulder drift ",shoulder_drift)
 check(shoulder_drift<1.2,"The pivot animation does not add another full turn to the visual body")
 p.fighter.camera=lab.camera
 fresh(2.0);await ticks(15)
 var max_step:=0.0
 var max_angle:=0.0
 for mode in [1,2,0]:
  lab.camera.mode=mode
  for i in 70:
   var previous: Vector3=lab.camera.global_position
   var previous_yaw: float=lab.camera.yaw
   await physics_frame
   max_step=maxf(max_step,previous.distance_to(lab.camera.global_position))
   max_angle=maxf(max_angle,absf(angle_difference(previous_yaw,lab.camera.yaw)))
 check(max_step<0.30 and max_angle<0.04,"Fight camera presets transition smoothly without snapping")
 fresh(0.75);await ticks(15)
 p.objective.health=1;r.objective.health=1
 p.fighter.request_move(&"punch_jab");r.fighter.request_move(&"punch_jab");await ticks(60)
 check(p.incapacitated and r.incapacitated and "무승부" in lab._result_label.text,"Same-frame double KO is a draw rather than an early winner")
 check(not is_instance_valid(lab.winner),"A double KO does not start a winner celebration")
 fresh();await ticks(15);r.objective.health=1
 p.fighter.request_move(&"punch_jab");await ticks(60)
 check(lab.winner==p and p.fighter.motion==&"celebration" and r.incapacitated,"A single KO starts the winner's supplied celebration")
 await ticks(160)
 check(p.fighter.move==&"victory_pose" and p.animation._action_node.animation==p.animation._clips.victory_pose,"The victory animation ends in a held victory pose")
 key(KEY_R);await ticks(5)
 check(p.fighter.motion!=&"celebration" and not is_instance_valid(lab.winner) and p.objective.health==100,"Reset clears celebration, defense bonuses and the round")
 var report:={"checks":checks,"failures":failures,"passed":failures.is_empty()}
 FileAccess.open("res://.tools/defense_test_results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("DEFENSE_TEST_RESULT ",JSON.stringify(report))
 quit(0 if failures.is_empty() else 1)

extends SceneTree
var lab
var p:HunterTarget
var r:HunterTarget
var checks:=0
var failures:Array[String]=[]
func _initialize():run.call_deferred()
func ticks(n:int):
 for i in n:await physics_frame
func check(value:bool,message:String):
 checks+=1
 if value:print("PASS: ",message)
 else:failures.append(message);printerr("FAIL: ",message)
func fresh(d:float=0.65):
 lab.reset_fight();lab._ai_toggle.button_pressed=false
 p.fighter.control=&"dummy";r.fighter.control=&"dummy"
 p.global_position=Vector3(0,0,d/2);r.global_position=Vector3(0,0,-d/2)
 p.visual.rotation.y=PI;r.visual.rotation.y=0.0
 p.physics_rig.reset_pose();r.physics_rig.reset_pose()
func key(code:int):
 var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=true;lab._unhandled_input(event)
func run():
 lab=load("res://scenes/hunter_fight_lab.tscn").instantiate();root.add_child(lab);current_scene=lab
 p=lab.player;r=lab.rival;lab._ai_toggle.button_pressed=false
 await ticks(25)
 fresh(4.0);await ticks(10);key(KEY_F);await ticks(1)
 check(p.fighter.motion==&"","F no longer starts the elbow")
 key(KEY_U);await ticks(1)
 check(p.fighter.move==&"elbow_strike","U starts the elbow attack")
 var elbow_frames:=1
 while p.fighter.active_windows().is_empty() and elbow_frames<20:
  await physics_frame;elbow_frames+=1
 check(elbow_frames<=5,"Elbow's active contact begins within roughly 0.064 seconds")
 var elapsed:=0.0
 while p.fighter.motion==&"attack" and elapsed<2.0:
  await physics_frame;elapsed+=1.0/60.0
 check(elapsed>1.1 and elapsed<1.4,"Elbow keeps the long one-second post-strike recovery")
 check(not p.fighter.request_move(&"elbow_strike"),"The elbow cannot restart immediately after recovery")
 check(p.fighter.request_move(&"punch_jab"),"Other attacks are available after elbow recovery")
 await ticks(50)
 check(p.fighter.request_move(&"elbow_strike"),"Elbow becomes available again after its 1.9-second reuse interval")
 fresh();await ticks(10)
 key(KEY_U)
 for i in 45:
  await physics_frame
  if r.objective.health<100:break
 check(r.objective.health<100,"The faster elbow still requires and lands real close-range elbow contact")
 fresh(4.0);await ticks(10);key(KEY_Q);await ticks(22)
 check(p.fighter.motion==&"parry" and p.fighter.can_parry(r,&"torso"),"Parry remains active after the previous 0.28-second limit")
 p.fighter.effects._process(0.0)
 var shells:=p.fighter.effects.arm_shells
 check(shells.size()==2 and shells[0].mesh.visible and shells[1].mesh.visible,"Both forearms are surrounded by a visible translucent guard shell")
 check(shells[0].mesh.global_position.distance_to(shells[0].area.global_position)<0.001,"The guard shell follows the actual animated forearm")
 await ticks(22)
 p.fighter.effects._process(0.0)
 check(p.fighter.motion==&"" and not shells[0].mesh.visible,"Guard and arm shells end cleanly after 0.68 seconds")
 for index in range(4):
  p.set_character(index);await ticks(10);fresh(4.0);await ticks(10)
  key(KEY_E);await ticks(8)
  p.fighter.effects._process(0.0)
  var first_opacity:float=p.fighter.effects.dodge_opacity
  var changed:=false
  for surface in p.fighter.effects.surfaces:
   if surface.mesh.get_surface_override_material(surface.surface)==surface.fade:changed=true
  await ticks(3);p.fighter.effects._process(0.0)
  var second_opacity:float=p.fighter.effects.dodge_opacity
  check(changed and first_opacity<0.9 and second_opacity<0.9 and absf(first_opacity-second_opacity)>0.05,"Character %d fades and visibly pulses during dodge"%index)
  await ticks(30);p.fighter.effects._process(0.0)
  var restored:=true
  for surface in p.fighter.effects.surfaces:restored=restored and surface.mesh.get_surface_override_material(surface.surface)==surface.source
  check(restored and is_equal_approx(p.fighter.effects.dodge_opacity,1.0),"Character %d restores all original materials after dodge"%index)
  fresh();await ticks(10);r.fighter.request_move(&"punch_jab")
  for i in 40:
   await physics_frame
   if p.objective.health<100:break
  p.fighter.effects._process(0.0)
  var flash:=false
  for surface in p.fighter.effects.surfaces:flash=flash or surface.mesh.material_overlay!=null
  check(p.objective.health<100 and flash and p.fighter.effects.hit_left>0.0,"Character %d receives a brief red flash from an actual hit"%index)
  await ticks(20);p.fighter.effects._process(0.0)
  check(p.fighter.effects.hit_left==0.0,"Character %d's red hit flash fades away"%index)
 key(KEY_R);await ticks(1)
 check(p.fighter.cooldowns.is_empty() and p.fighter.effects.hit_left==0.0,"Reset clears both elbow cooldown and temporary effects")
 var report:={"checks":checks,"failures":failures,"passed":failures.is_empty()}
 FileAccess.open("res://.tools/combat_effects_test_results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("COMBAT_EFFECTS_TEST_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)

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
func fresh(distance: float=0.80) -> void:
 lab.reset_fight();lab._ai_toggle.button_pressed=false
 p.fighter.control=&"dummy";r.fighter.control=&"dummy"
 p.global_position=Vector3(0,0,distance/2);r.global_position=Vector3(0,0,-distance/2)
 p.visual.rotation.y=PI;r.visual.rotation.y=0.0
 p.physics_rig.reset_pose();r.physics_rig.reset_pose();contacts.clear()
func key(code: int) -> void:
 var event:=InputEventKey.new();event.physical_keycode=code;event.pressed=true
 lab._unhandled_input(event)
func run() -> void:
 lab=load("res://scenes/hunter_fight_lab.tscn").instantiate();root.add_child(lab);current_scene=lab
 p=lab.player;r=lab.rival;lab._ai_toggle.button_pressed=false
 await ticks(25)
 p.fighter.strike_landed.connect(func(c: Dictionary):contacts.append(c))
 check(HunterAnimation.CHARACTERS.size()==4,"There are four independently selectable characters")
 check(HunterAnimation.CHARACTERS[0].number==1 and HunterAnimation.CHARACTERS[1].number==2 and HunterAnimation.CHARACTERS[2].number==3,"Original character numbers stay unchanged")
 check(lab._player_picker.get_item_text(0).begins_with("0") and lab._player_picker.get_item_id(0)==3,"The visible picker lists the new number zero first with a stable model ID")
 key(KEY_0);await ticks(10)
 check(p.character_index==3 and lab._player_picker.get_selected_id()==3,"Number 0 selects the supplied orange restyle model")
 check(p.animation._clips.size()==45 and p.animation._clips.has("punch_quad"),"The new model has the full movement, defense and combat motion set")
 check(p.physics_rig.parts.size()==15 and p.fighter.boxes.hurtboxes.size()==15 and p.fighter.boxes.hitboxes.size()==10,"The new model has physical body parts and separate combat contact shapes")
 check(p.animation.cloth.panels.size()==16 and p.animation.hair_motion.strands.size()==24,"The long coat and short hair have secondary motion")
 var blend_shapes:=0
 var normal_mapped_hair:=false
 for mesh in p.visual.get_node("Model").find_children("*","MeshInstance3D",true,false):
  if mesh.mesh is ArrayMesh:blend_shapes+=mesh.mesh.get_blend_shape_count()
  for surface in mesh.mesh.get_surface_count():
   var material: Material=mesh.get_active_material(surface)
   if material is StandardMaterial3D and material.resource_name.begins_with("HunterHair_"):
    normal_mapped_hair=normal_mapped_hair or (material.albedo_texture!=null and material.normal_enabled)
 check(blend_shapes>=17,"The supplied face expression shapes survive retargeting")
 check(normal_mapped_hair,"The orange hair keeps its supplied color and normal textures")
 fresh(0.72);await ticks(15);key(KEY_I);await ticks(1)
 check(p.fighter.move==&"punch_quad","The previous number one's four-punch special now belongs to number zero")
 await ticks(90)
 check(not contacts.is_empty() and r.objective.health<100.0,"The new number zero's four-punch special damages through real hand contact")
 for kick in HunterCombatMoves.CHARACTER_KICKS[3]:
  fresh(1.1 if kick in [&"kick_d",&"kick_martelo"] else 0.8);await ticks(15)
  p.fighter.request_move(kick);await ticks(95)
  check(not contacts.is_empty() and r.objective.health<100.0,"Number zero can land its own kick %s"%kick)
 check(HunterCombatMoves.CHARACTER_KICKS[3]!=HunterCombatMoves.CHARACTER_KICKS[0],"Numbers zero and one have different kick repertoires")
 fresh(4.0);p.fighter.control=&"player";p.fighter.camera=null
 await ticks(10);var start:=p.global_position
 Input.action_press("fight_forward");await ticks(30);Input.action_release("fight_forward")
 check(p.global_position.distance_to(start)>0.8,"The new model supports manual movement")
 key(KEY_E);await ticks(35)
 check(p.fighter.counter_left==0.0 and p.fighter.motion==&"","Empty dodges work and grant no counter reward for number zero")
 p.knock_down();await ticks(250)
 check(not p.is_fallen(),"The new model can fall and get up through the existing physics system")
 p.fighter.camera=lab.camera
 key(KEY_F1);await ticks(10)
 check(p.character_index==0,"F1 still selects the original number one")
 fresh(4.0);await ticks(15);key(KEY_I);await ticks(1)
 check(p.fighter.move==&"special_capoeira","Number one's I starts the two supplied kick motions as one special")
 var animation_key: StringName=p.animation._action_node.animation
 check(animation_key==p.animation._clips.special_capoeira,"The special uses the baked Armada and Martelo Do Chau sequence")
 var parts: Array=[]
 for i in 100:
  await physics_frame
  for w in p.fighter.active_windows():
   if not w.part in parts:parts.append(w.part)
 check(parts.has(&"left_foot") and parts.has(&"right_foot"),"Both supplied kicks have distinct physical foot attack windows")
 check(r.objective.health==100.0,"The two-kick special cannot cause damage without actual overlap")
 var hit_windows: Dictionary={}
 var combined_landed:=false
 for distance in [0.8,1.0,1.2,1.4]:
  fresh(distance);await ticks(15);key(KEY_I);await ticks(120)
  var seen: Dictionary={}
  for c in contacts:
   hit_windows[c.window]=true;seen[c.window]=true
  combined_landed=combined_landed or seen.size()==2
  print("CAPOEIRA_CONTACT ",distance," hp=",r.objective.health," ",contacts.map(func(c: Dictionary):return [c.window,c.attack_part,c.hurt_part,c.damage]))
 check(hit_windows.has(0),"Armada's left foot can hit an actual opponent")
 check(hit_windows.has(1),"Martelo Do Chau's right foot can hit an actual opponent")
 check(combined_landed,"Both kicks can connect in the same special at the right distance")
 lab._rival_picker.item_selected.emit(lab._rival_picker.get_item_index(3));await ticks(10)
 check(r.character_index==3,"The new zero model is also selectable as an opponent")
 key(KEY_R);await ticks(5)
 check(r.objective.health==100 and not p.fighter.round_over,"Reset still clears the four-character fight")
 var report:={"checks":checks,"failures":failures,"passed":failures.is_empty()}
 FileAccess.open("res://.tools/zero_character_test_results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("ZERO_CHARACTER_TEST_RESULT ",JSON.stringify(report))
 quit(0 if failures.is_empty() else 1)

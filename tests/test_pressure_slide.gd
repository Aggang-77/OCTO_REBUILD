extends SceneTree
var lab
var p:HunterTarget
var r:HunterTarget
var hits:Array[Dictionary]=[]
var checks:=0
var failures:Array[String]=[]
func _initialize():run.call_deferred()
func ticks(n:int):
 for i in n:await physics_frame
func check(value:bool,message:String):
 checks+=1
 if value:print("PASS: ",message)
 else:failures.append(message);printerr("FAIL: ",message)
func fresh(d:float=0.75):
 lab.reset_fight();lab._ai_toggle.button_pressed=false
 p.fighter.control=&"dummy";r.fighter.control=&"dummy"
 p.global_position=Vector3(0,0,d/2);r.global_position=Vector3(0,0,-d/2)
 p.visual.rotation.y=PI;r.visual.rotation.y=0.0
 p.physics_rig.reset_pose();r.physics_rig.reset_pose();hits.clear()
func run():
 lab=load("res://scenes/hunter_fight_lab.tscn").instantiate();root.add_child(lab);current_scene=lab
 p=lab.player;r=lab.rival;lab._ai_toggle.button_pressed=false
 await ticks(30)
 p.fighter.strike_landed.connect(func(c:Dictionary):hits.append(c))
 var trips:=0
 for index in range(4):
  p.set_character(index);await ticks(10)
  fresh(1.30);await ticks(15);p.fighter.request(&"slide")
  await ticks(90)
  print("SLIDE_CONTACT ",index," ",hits.map(func(c:Dictionary):return [c.attack_part,c.hurt_part,c.damage,c.get("trip",false),c.get("impact_speed",0)]))
  check(not hits.is_empty() and r.objective.health<100,"Character %d's slide deals real foot/body contact damage"%index)
  check(hits.size()<=1,"Character %d's slide cannot repeatedly hit the same target"%index)
  if not hits.is_empty() and hits[0].get("trip",false):trips+=1
  check(r.is_fallen(),"Character %d's fast leg contact physically trips the opponent"%index)
 check(trips==4,"All four models can land a fast sliding leg trip")
 fresh(6.0);await ticks(15);p.fighter.request(&"slide");await ticks(100)
 check(hits.is_empty() and r.objective.health==100,"A sliding miss causes no damage or knockdown")
 p.set_character(0);await ticks(10)
 fresh(0.65);await ticks(15)
 p.fighter.request_move(&"punch_quad")
 for i in 80:
  await physics_frame
  if r.fighter.pressure_hits>=2 and r.fighter.motion==&"reaction":break
 check(r.fighter.pressure_hits>=2 and r.fighter.motion==&"reaction","Repeated real combo contacts build pressure on the victim")
 r.fighter.request(&"dodge")
 var time_to_escape:=0
 while r.fighter.motion!=&"dodge" and time_to_escape<30:
  await physics_frame;time_to_escape+=1
 check(r.fighter.motion==&"dodge" and time_to_escape<=10,"E breaks the repeated-hit stun after its short minimum reaction")
 check(r.fighter.escape_cooldown>1.8 and r.stamina<86,"Pressure escape consumes extra stamina and starts its reuse limit")
 check(r.fighter.counter_left==0,"Pressure escape itself does not award a free successful-defense bonus")
 var start:=r.global_position;await ticks(30)
 check(r.global_position.distance_to(start)>0.5,"The escape moves the real body out of close combo range")
 fresh(0.65);await ticks(15)
 p.fighter.request_move(&"punch_jab")
 for i in 40:
  await physics_frame
  if r.fighter.motion==&"reaction":break
 r.fighter.request(&"dodge");await ticks(8)
 check(r.fighter.motion==&"reaction" and r.fighter.pressure_hits==1,"One isolated hit retains its normal reaction stun")
 fresh(0.65);await ticks(15);r.stamina=5
 p.fighter.request_move(&"punch_quad")
 for i in 80:
  await physics_frame
  if r.fighter.pressure_hits>=2:break
 r.fighter.request(&"dodge");await ticks(8)
 check(r.fighter.motion==&"reaction","Pressure escape is unavailable without sufficient stamina")
 p.set_character(3);await ticks(10);fresh(4);await ticks(10)
 var eased:=false
 for material in p.animation.skirt_materials:
  eased=eased or float(material.get_shader_parameter("coat_ease"))>=0.028
 check(eased,"The zero model's coat receives extra body clearance and hem flare")
 check(p.visual.get_node("Model").find_child("Lily_Coat",true,false)!=null,"Number zero actually loads the supplied coat model")
 var report:={"checks":checks,"failures":failures,"passed":failures.is_empty()}
 FileAccess.open("res://.tools/pressure_slide_test_results.json",FileAccess.WRITE).store_string(JSON.stringify(report,"  "))
 print("PRESSURE_SLIDE_TEST_RESULT ",JSON.stringify(report));quit(0 if failures.is_empty() else 1)

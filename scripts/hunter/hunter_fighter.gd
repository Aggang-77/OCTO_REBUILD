class_name HunterFighter
extends Node
signal strike_landed(contact: Dictionary)
signal hit_received(contact: Dictionary)
signal knocked_out(attacker: HunterTarget)
signal reaction_started(clip: StringName, hurt_part: StringName)
signal defense_succeeded(kind: StringName)
signal pressure_escaped(kind: StringName)
const COUNTER_WINDOW: float=1.2
const COUNTER_WINDUP: float=1.45
var actor: HunterTarget
var enabled: bool=true
var control: StringName=&"player"
var team: int=0
var opponent: HunterTarget
var camera: Camera3D
var boxes: HunterCombatHitboxes
var effects: HunterCombatEffects
var move: StringName=&""
var motion: StringName=&""
var elapsed: float=0.0
var duration: float=0.0
var rate: float=1.0
var source_time: float=0.0
var round_over: bool=false
var last_hit: Dictionary={}
var last_reaction: StringName=&""
var debug_hitboxes: bool=false
var counter_left: float=0.0
var counter_attack: bool=false
var attack_serial: int=0
var _parried_serial: int=-1
var _pending: StringName=&""
var _buffer_left: float=0.0
var _hit_targets: Dictionary={}
var cooldowns: Dictionary={}
var pressure_hits: int=0
var pressure_left: float=0.0
var pressure_stun_time: float=0.0
var escape_cooldown: float=0.0
var escape_armor_left: float=0.0
var _punch_index: int=0
var _kick_index: int=0
var _chain_left: float=0.0
var _ai_left: float=1.0
var _ai_index: int=0
var _direction:=Vector3.BACK
var _turn_from: float=0.0
var _turn_to: float=0.0
var _turn_cooldown: float=0.0
var _input_vector:=Vector2.ZERO
var _input_frame:=Basis.IDENTITY
var _defense_cooldown: float=0.0
var _dodge_threatened: bool=false
var _dodge_hit: bool=false
var _trade_left: float=0.0
var _trade_part: StringName=&""
var clinch_victim: HunterTarget
var clinch_holder: HunterTarget
var _clinch_grips: Array[int]=[]
var _root_shape: CapsuleShape3D
var _root_height: float=1.7
var _root_center: Vector3
var knockout_reaction_left: float=0.0
var _knockdown_impulse:=Vector3.ZERO

static func install_inputs() -> void:
 for entry in [["fight_left",KEY_A],["fight_right",KEY_D],["fight_forward",KEY_W],["fight_back",KEY_S],["fight_run",KEY_SHIFT]]:
  if InputMap.has_action(entry[0]):continue
  InputMap.add_action(entry[0])
  var event:=InputEventKey.new()
  event.physical_keycode=entry[1]
  InputMap.action_add_event(entry[0],event)

func setup(value: HunterTarget) -> void:
 actor=value
 install_inputs()
 var collision: CollisionShape3D=actor.get_node("CollisionShape3D")
 collision.shape=collision.shape.duplicate()
 _root_shape=collision.shape
 _root_height=_root_shape.height
 _root_center=collision.position
 actor.collision_mask|=2
 actor.animation.model_ready.connect(_model_ready)
 if is_instance_valid(actor.animation.skeleton):_model_ready(actor.character_index)

func _model_ready(_index: int) -> void:
 if not is_instance_valid(boxes):
  boxes=HunterCombatHitboxes.new()
  boxes.name="CombatHitAndHurtBoxes"
  actor.add_child(boxes)
 boxes.setup(actor,self)
 boxes.set_debug_visible(debug_hitboxes)
 if not is_instance_valid(effects):
  effects=HunterCombatEffects.new()
  effects.name="CombatVisualEffects"
  actor.add_child(effects)
 effects.setup(self)
 actor.animation.set_combat_stance(true)
 actor.animation.set_weapon_visible(false)

func reset_fighter() -> void:
 interrupt()
 _pending=&""
 _buffer_left=0.0
 round_over=false
 counter_left=0.0
 cooldowns.clear()
 pressure_hits=0
 pressure_left=0.0
 pressure_stun_time=0.0
 escape_cooldown=0.0
 if is_instance_valid(effects):effects.reset_effects()
 _punch_index=0
 _kick_index=0
 _chain_left=0.0
 _ai_left=1.0
 _defense_cooldown=0.0
 _turn_cooldown=0.0
 _input_vector=Vector2.ZERO
 attack_serial+=1
 last_hit.clear()
 last_reaction=&""
 actor.animation.set_combat_stance(true)
 actor.animation.set_weapon_visible(false)

func interrupt() -> void:
 escape_armor_left=0.0
 _release_clinch()
 clinch_holder=null
 motion=&""
 move=&""
 elapsed=0.0
 source_time=0.0
 duration=0.0
 counter_attack=false
 _trade_left=0.0
 _trade_part=&""
 _hit_targets.clear()
 knockout_reaction_left=0.0
 _knockdown_impulse=Vector3.ZERO
 _restore_capsule()
 if is_instance_valid(boxes):
  boxes.deactivate_attacks()
  boxes.clear_dodge_trace()

func set_debug(value: bool) -> void:
 debug_hitboxes=value
 if is_instance_valid(boxes):boxes.set_debug_visible(value)

func request(command: StringName) -> void:
 if not enabled or round_over or actor.incapacitated or actor.is_fallen():return
 _pending=command
 _buffer_left=0.42

func request_move(kind: StringName) -> bool:
 if not HunterCombatMoves.MOVES.has(kind) or not _can_start():return false
 var data: Dictionary=HunterCombatMoves.MOVES[kind]
 if float(cooldowns.get(kind,0.0))>0.0:return false
 if actor.stamina<float(data["stamina"]):return false
 var part:=HunterCombatMoves.physical_part(data["windows"][0][2])
 var mobility:=actor.physics_rig.get_mobility(part) if is_instance_valid(actor.physics_rig) else 1.0
 actor.animation.cancel_action()
 rate=float(data["rate"])*lerpf(0.60,1.0,mobility)
 counter_attack=counter_left>0.0
 var windup_rate:=rate*(COUNTER_WINDUP if counter_attack else 1.0)
 duration=actor.animation.play_clip(String(data.get("clip",kind)),windup_rate)
 if duration<=0.0:return false
 if counter_attack:counter_left=0.0
 motion=&"attack"
 move=kind
 elapsed=0.0
 source_time=0.0
 attack_serial+=1
 cooldowns[kind]=float(data.get("cooldown",0.0))
 _hit_targets.clear()
 _direction=actor.visual.global_basis.z
 _direction.y=0.0
 _direction=_direction.normalized()
 actor.stamina-=float(data["stamina"])
 actor._set_state(kind)
 return true

func _can_start() -> bool:
 return enabled and not round_over and not actor.incapacitated and not actor.is_fallen() and motion==&"" and is_instance_valid(actor.animation.tree)

func active_windows() -> Array[Dictionary]:
 var result: Array[Dictionary]=[]
 if motion not in [&"attack",&"slide"] or round_over or actor.incapacitated or actor.is_fallen() or not HunterCombatMoves.MOVES.has(move):return result
 var windows: Array=HunterCombatMoves.MOVES[move]["windows"]
 for index in range(windows.size()):
  var window: Array=windows[index]
  if source_time>=float(window[0]) and source_time<=float(window[1]):result.append({"id":int(window[3]) if window.size()>3 else index,"part":window[2]})
 return result

func can_hit(victim: HunterTarget, window_id: int) -> bool:
 return victim!=actor and not victim.incapacitated and not round_over and not _hit_targets.has("%d:%d"%[window_id,victim.get_instance_id()])

func resolve_contact(victim: HunterTarget, window_id: int, attack_part: StringName, hurt_part: StringName, point: Vector3) -> void:
 if motion not in [&"attack",&"slide"] or not can_hit(victim,window_id):return
 _hit_targets["%d:%d"%[window_id,victim.get_instance_id()]]=true
 var data: Dictionary=HunterCombatMoves.MOVES[move]
 var efficiency:=actor.physics_rig.get_mobility(HunterCombatMoves.physical_part(attack_part)) if is_instance_valid(actor.physics_rig) else 1.0
 var base_damage: float=data["window_damage"][window_id] if data.has("window_damage") else data["damage"]
 var damage:=base_damage*HunterCombatMoves.damage_multiplier(hurt_part)*efficiency
 var contact:={"attacker":actor,"victim":victim,"move":move,"attack_part":attack_part,"hurt_part":hurt_part,"position":point,"damage":damage,"window":window_id,"serial":attack_serial,"parried":victim.fighter.can_parry(actor,hurt_part)}
 if move==&"slide":
  var speed:=Vector2(actor.velocity.x,actor.velocity.z).length()
  var trippable:=hurt_part in [&"left_thigh",&"right_thigh",&"left_shin",&"right_shin",&"left_foot",&"right_foot"]
  contact["trip"]=trippable and speed>=2.8 and victim.is_on_floor() and not victim.is_fallen()
  contact["impact_speed"]=speed
 if move==&"special_clinch" and "hand" in attack_part:
  contact["grab"]=true
  contact["damage"]=0.0
 # Resolve after both skeletons have sampled. A contact already made survives
 # the attacker's same-frame hit reaction, so simultaneous blows can trade.
 _deliver_contact.call_deferred(contact,float(data["impulse"])*efficiency)

func _deliver_contact(contact: Dictionary, impulse: float) -> void:
 if not is_inside_tree() or not is_instance_valid(contact["victim"]):return
 if int(contact["serial"])==_parried_serial:return
 var victim: HunterTarget=contact["victim"]
 if contact["parried"]:
  contact["damage"]=0.0
  victim.fighter._award_counter(&"parry")
  _receive_parry(int(contact["serial"]))
 elif contact.get("grab",false):_start_clinch(victim)
 else:victim.fighter.receive_strike(contact,impulse)
 strike_landed.emit(contact)

func can_parry(attacker: HunterTarget, part: StringName) -> bool:
 if motion!=&"parry" or elapsed<0.08 or elapsed>0.48:return false
 if part in [&"pelvis",&"left_thigh",&"right_thigh",&"left_shin",&"right_shin",&"left_foot",&"right_foot"]:return false
 var toward:=actor.global_position.direction_to(attacker.global_position)
 toward.y=0.0
 return actor.visual.global_basis.z.dot(toward.normalized())>0.35

func _award_counter(kind: StringName) -> void:
 counter_left=COUNTER_WINDOW
 defense_succeeded.emit(kind)

func _receive_parry(serial: int) -> void:
 _parried_serial=serial
 if actor.incapacitated:return
 interrupt()
 actor.animation.cancel_action()
 rate=1.8
 actor.animation.play_clip("stunned",rate)
 duration=0.30
 motion=&"stagger"
 actor._set_state(&"parried")

func note_dodge_threat() -> void:
 if motion==&"dodge":_dodge_threatened=true

func accepts_hurt_part(part: StringName, hurt: StringName) -> bool:
 if move==&"special_clinch" and "hand" in part:return hurt==&"head"
 return true

func _start_clinch(victim: HunterTarget) -> void:
 if motion!=&"attack" or move!=&"special_clinch" or victim.incapacitated:return
 clinch_victim=victim
 victim.fighter.interrupt()
 victim.fighter.clinch_holder=actor
 victim.animation.cancel_action()
 victim.animation.play_clip("body_block",1.0)
 victim.fighter.motion=&"clinched"
 victim.fighter.duration=0.9
 victim._set_state(&"clinched")
 var head: Area3D=victim.fighter.boxes.hurtboxes[&"head"]["area"]
 for part in [&"left_hand",&"right_hand"]:
  var hand:=actor.physics_rig.get_part_body(part)
  _clinch_grips.append(victim.physics_rig.attach_grip(&"head",hand,head.global_position,650.0,28.0,95.0,0.65))
 actor.animation.play_clip("knee",rate)
 source_time=1.0
 elapsed=0.0

func _release_clinch() -> void:
 if is_instance_valid(clinch_victim):
  if is_instance_valid(clinch_victim.physics_rig):
   for id in _clinch_grips:clinch_victim.physics_rig.release_grip(id)
  if is_instance_valid(clinch_victim.fighter) and clinch_victim.fighter.clinch_holder==actor:
   clinch_victim.fighter.clinch_holder=null
   if clinch_victim.fighter.motion==&"clinched":
    clinch_victim.animation.cancel_action()
    clinch_victim.fighter.motion=&""
 _clinch_grips.clear()
 clinch_victim=null

func receive_strike(contact: Dictionary, impulse_strength: float) -> void:
 if actor.incapacitated or round_over:return
 pressure_hits=pressure_hits+1 if pressure_left>0.0 else 1
 if pressure_hits==1:pressure_stun_time=0.0
 pressure_left=1.0
 _dodge_hit=true
 last_hit=contact
 var attacker: HunterTarget=contact["attacker"]
 var part: StringName=contact["hurt_part"]
 var direction:=actor.global_position-attacker.global_position
 direction.y=0.0
 if direction.length()<0.01:direction=attacker.visual.global_basis.z
 direction=direction.normalized()
 actor.apply_damage(contact["damage"])
 actor.physics_rig.apply_part_impulse(part,direction*impulse_strength+Vector3.UP*0.15,contact["position"])
 hit_received.emit(contact)
 if actor.incapacitated:
  _begin_reaction(part)
  knockout_reaction_left=0.22
  _knockdown_impulse=direction*7.0+Vector3.UP
  knocked_out.emit(attacker)
  return
 if contact.get("trip",false):
  _begin_reaction(part)
  _knockdown_impulse=direction*7.0+Vector3.UP*0.8
  return
 # A pressure escape can survive one grazing light blow while the body starts
 # moving. It still loses health and cannot earn a clean dodge counter bonus.
 if escape_armor_left>0.0 and motion in [&"parry",&"dodge"] and float(contact["damage"])<28.0:return
 # A near-active attack gets a small trade window, not immunity to damage.
 if motion==&"attack" and not active_windows().is_empty():
  _trade_left=0.075
  _trade_part=part
 elif motion==&"attack" and float(HunterCombatMoves.MOVES[move]["windows"][0][0])-source_time<rate*0.075:
  _trade_left=0.075
  _trade_part=part
 else:_begin_reaction(part)
 if float(contact["damage"])>=28.0 and part==&"head":_knockdown_impulse=direction*7.0+Vector3.UP

func _begin_reaction(part: StringName) -> void:
 interrupt()
 actor.animation.cancel_action()
 var clip: String
 if part==&"head":clip=["hit_head_a","hit_head_b","hit_head_c"][_ai_index%3]
 else:clip=["hit_body_a","hit_body_b"][_ai_index%2]
 _ai_index+=1
 rate=2.35
 actor.animation.play_clip(clip,rate)
 duration=0.36 if part==&"head" else 0.30
 motion=&"reaction"
 move=StringName(clip)
 elapsed=0.0
 actor._set_state(&"hit_head" if part==&"head" else &"hit_body")
 last_reaction=StringName(clip)
 reaction_started.emit(last_reaction,part)

func tick_knockout_reaction(delta: float) -> void:
 knockout_reaction_left=maxf(0.0,knockout_reaction_left-delta)
 elapsed+=delta
 _move_root(Vector3.ZERO,delta)
 if knockout_reaction_left<=0.0:
  var impulse:=_knockdown_impulse
  actor.knock_down(impulse)
  actor._set_state(&"knocked_out")

func start_celebration() -> void:
 interrupt()
 round_over=true
 actor.animation.cancel_action()
 duration=actor.animation.play_clip("celebrate",1.0)
 motion=&"celebration"
 actor._set_state(&"celebrating")

func tick(delta: float) -> void:
 for kind in cooldowns:cooldowns[kind]=maxf(0.0,float(cooldowns[kind])-delta)
 pressure_left=maxf(0.0,pressure_left-delta)
 escape_cooldown=maxf(0.0,escape_cooldown-delta)
 escape_armor_left=maxf(0.0,escape_armor_left-delta)
 if pressure_left<=0.0:pressure_hits=0
 if motion==&"reaction":pressure_stun_time+=delta
 _chain_left=maxf(0.0,_chain_left-delta)
 _buffer_left=maxf(0.0,_buffer_left-delta)
 _turn_cooldown=maxf(0.0,_turn_cooldown-delta)
 _defense_cooldown=maxf(0.0,_defense_cooldown-delta)
 counter_left=maxf(0.0,counter_left-delta)
 if _buffer_left<=0.0:_pending=&""
 if motion==&"celebration":
  elapsed+=delta
  _move_root(Vector3.ZERO,delta)
  if elapsed<0.6 and is_instance_valid(camera):actor._face(camera.global_position,1.0-exp(-delta*4.0))
  if elapsed>=duration and move!=&"victory_pose":
   actor.animation.play_clip("victory_pose")
   move=&"victory_pose"
  return
 if round_over:
  actor._brake(delta)
  actor.animation.play_state(&"idle",0.0)
  return
 var desired:=_read_direction()
 _try_pressure_escape(desired)
 if control==&"sparring":
  _ai_left-=delta
  if is_instance_valid(opponent) and not opponent.incapacitated:
   var offset:=opponent.global_position-actor.global_position
   offset.y=0.0
   desired=offset.normalized() if offset.length()>0.90 else Vector3.ZERO
   if motion==&"":actor._face(opponent.global_position,minf(1.0,delta*12.0))
   if offset.length()<1.60 and _ai_left<=0.0 and motion==&"":
    var kicks: Array=HunterCombatMoves.CHARACTER_KICKS[actor.character_index]
    var choices: Array=[&"punch_jab",&"punch_cross",kicks[0],&"elbow_strike",&"punch_hook"]
    var choice: StringName=choices[_ai_index%choices.size()]
    if offset.length()>1.05:choice=kicks[_ai_index%kicks.size()]
    request_move(choice)
    _ai_index+=1
    _ai_left=0.9
 elif control==&"dummy":
  desired=Vector3.ZERO
  if is_instance_valid(opponent) and motion==&"":actor._face(opponent.global_position,minf(1.0,delta*6.0))
 if _pending!=&"" and motion==&"":_consume_command(desired)
 if motion!=&"":
  elapsed+=delta
  _tick_motion(delta,desired)
  actor.stamina=minf(actor.profile.max_stamina,actor.stamina+3.0*delta)
  return
 var horizontal:=Vector2(actor.velocity.x,actor.velocity.z).length()
 if desired.length()>0.1 and horizontal>1.0 and _turn_cooldown<=0.0:
  if actor.visual.global_basis.z.dot(desired)<-0.82:
   _start_turn(desired)
   _move_root(Vector3.ZERO,delta)
   return
 if desired.length()>0.1 and control==&"player":
  actor.visual.rotation.y=rotate_toward(actor.visual.rotation.y,atan2(desired.x,desired.z),delta*8.0)
 var running:=control==&"player" and Input.is_action_pressed("fight_run") and actor.stamina>8.0
 var speed:=5.0 if running else (2.1 if control==&"sparring" else 3.0)
 if is_instance_valid(actor.capture_source):speed=0.0
 _move_root(desired*speed,delta)
 actor.stamina=clampf(actor.stamina+(-5.0 if running and desired.length()>0.1 else 12.0)*delta,0.0,actor.profile.max_stamina)
 horizontal=Vector2(actor.velocity.x,actor.velocity.z).length()
 actor._set_state(&"fight_move" if horizontal>0.1 else &"fight_idle")
 actor.animation.play_state(&"flee" if horizontal>0.1 else &"idle",horizontal)

func _read_direction() -> Vector3:
 if control!=&"player":return Vector3.ZERO
 var input:=Input.get_vector("fight_left","fight_right","fight_forward","fight_back")
 # Keep a held movement direction stable while the follow camera swings.
 if input!=_input_vector:
  _input_frame=camera.global_basis if is_instance_valid(camera) else Basis.IDENTITY
  _input_vector=input
 var forward: Vector3=-_input_frame.z
 forward.y=0.0
 var right: Vector3=_input_frame.x
 right.y=0.0
 return (right.normalized()*input.x-forward.normalized()*input.y).limit_length(1.0)

func _consume_command(desired: Vector3) -> void:
 var command:=_pending
 _pending=&""
 if command in [&"parry",&"dodge"]:
  _start_defense(command,desired)
  return
 if command==&"slide":
  if actor.stamina<12.0:return
  _direction=desired if desired.length()>0.1 else actor.visual.global_basis.z
  _direction.y=0.0
  _direction=_direction.normalized()
  actor.visual.rotation.y=atan2(_direction.x,_direction.z)
  actor.animation.cancel_action()
  rate=1.45
  duration=actor.animation.play_clip("slide",rate)
  if duration<=0.0:return
  motion=&"slide"
  move=&"slide"
  elapsed=0.0
  source_time=0.0
  attack_serial+=1
  _hit_targets.clear()
  actor.stamina-=12.0
  actor._set_state(&"sliding")
  return
 var kind:=command
 if command==&"special":kind=HunterCombatMoves.SPECIALS[actor.character_index]
 if command==&"punch":
  if _chain_left<=0.0:_punch_index=0
  kind=HunterCombatMoves.PUNCHES[_punch_index%HunterCombatMoves.PUNCHES.size()]
 elif command==&"kick":
  var kicks: Array=HunterCombatMoves.CHARACTER_KICKS[actor.character_index]
  kind=kicks[_kick_index%kicks.size()]
 if request_move(kind):
  if command==&"punch":_punch_index+=1
  if command==&"kick":_kick_index+=1
  _chain_left=1.2

func can_pressure_escape() -> bool:
 return motion==&"reaction" and pressure_stun_time>=0.12 and pressure_hits>=2 and escape_cooldown<=0.0 and _defense_cooldown<=0.0 and actor.stamina>=20.0 and _knockdown_impulse.length()<0.01

func _try_pressure_escape(desired: Vector3) -> void:
 if _pending not in [&"parry",&"dodge"] or not can_pressure_escape():return
 var command:=_pending
 _pending=&""
 actor.animation.cancel_action()
 interrupt()
 _start_defense(command,desired,20.0)
 if motion==command:
  pressure_hits=0
  pressure_left=0.0
  escape_cooldown=2.0
  escape_armor_left=0.16
  pressure_escaped.emit(command)

func _start_defense(kind: StringName, desired: Vector3, cost: float=10.0) -> void:
 if not _can_start() or _defense_cooldown>0.0 or actor.stamina<cost:return
 actor.animation.cancel_action()
 elapsed=0.0
 motion=kind
 move=kind
 actor.stamina-=cost
 _defense_cooldown=0.65
 if kind==&"parry":
  rate=2.5
  actor.animation.play_clip("parry",rate)
  duration=0.68
  _defense_cooldown=0.85
  actor._set_state(&"parrying")
 else:
  _direction=desired if desired.length()>0.1 else -actor.visual.global_basis.z
  _direction.y=0.0
  _direction=_direction.normalized()
  rate=3.0
  actor.animation.play_clip("dodge",rate)
  duration=0.50
  _dodge_threatened=false
  _dodge_hit=false
  boxes.begin_dodge_trace()
  actor._set_state(&"dodging")

func _start_turn(desired: Vector3) -> void:
 _turn_from=actor.visual.rotation.y
 _turn_to=atan2(desired.x,desired.z)
 actor.animation.cancel_action()
 actor.animation.play_clip("pivot",2.5)
 duration=0.34
 motion=&"turn"
 move=&"pivot"
 elapsed=0.0
 actor._set_state(&"turning")

func _tick_motion(delta: float, desired: Vector3) -> void:
 var phase:=elapsed/maxf(duration,0.01)
 if motion==&"slide":
  source_time=elapsed*rate
  if phase>0.13 and phase<0.82:
   _root_shape.height=0.68
   actor.get_node("CollisionShape3D").position=Vector3(0,0.36,0)
  else:_restore_capsule()
  _move_root(_direction*lerpf(5.8,0.25,smoothstep(0.0,1.0,phase)),delta,25.0)
 elif motion==&"dodge":
  _move_root(_direction*(3.8*sin(PI*clampf(phase,0.0,1.0))),delta,32.0)
 elif motion==&"turn":
  actor.visual.rotation.y=lerp_angle(_turn_from,_turn_to,smoothstep(0.03,0.95,phase))
  _move_root(Vector3.ZERO,delta)
 elif motion==&"attack":
  var data: Dictionary=HunterCombatMoves.MOVES[move]
  var first: float=data["windows"][0][0]
  var last: float=data["windows"][-1][1]
  var playback:=rate*(COUNTER_WINDUP if counter_attack and source_time<first else 1.0)
  var full_recovery: bool=data.get("full_recovery",false)
  var clip_length:=0.0
  if full_recovery:
   clip_length=actor.animation.player.get_animation(actor.animation._clips[String(data.get("clip",move))]).length
   if source_time>=last:playback=(clip_length-last)/float(data["recovery"])
  # Split a frame crossing the windup boundary so speed never leaks into impact.
  var advance:=delta*playback
  if source_time<first and source_time+advance>first:
   advance=first-source_time+(delta-(first-source_time)/playback)*rate
  source_time+=advance
  actor.animation.set_action_rate(playback)
  if move==&"special_clinch" and not is_instance_valid(clinch_victim) and source_time>0.58:
   _finish_motion(desired)
   return
  if source_time<first*0.6 and is_instance_valid(opponent):
   var toward:=opponent.global_position-actor.global_position
   toward.y=0.0
   if toward.length()<2.1 and toward.normalized().dot(actor.visual.global_basis.z)>0.65:
    actor._face(opponent.global_position,minf(1.0,delta*7.0))
    _direction=actor.visual.global_basis.z
  var step_end:=maxf(0.12,last/rate*0.8)
  var step: float=data["step"]
  _move_root(_direction*(step/step_end if elapsed<step_end else 0.0),delta)
  if _trade_left>0.0:
   _trade_left-=delta
   if _trade_left<=0.0:
    var knockdown:=_knockdown_impulse
    _begin_reaction(_trade_part)
    _knockdown_impulse=knockdown
    return
  if source_time>=(clip_length if full_recovery else last+float(data["recovery"])*rate):
   _finish_motion(desired)
   return
 else:_move_root(Vector3.ZERO,delta)
 if motion==&"reaction" and _knockdown_impulse.length()>0.01 and elapsed>=0.22:
  actor.knock_down(_knockdown_impulse)
  return
 if motion!=&"attack" and elapsed>=duration:_finish_motion(desired)

func _finish_motion(desired: Vector3) -> void:
 if motion==&"dodge" and _dodge_threatened and not _dodge_hit:_award_counter(&"dodge")
 if motion==&"turn":
  actor.visual.rotation.y=_turn_to
  _turn_cooldown=0.3
 actor.animation.fade_action()
 interrupt()
 if _pending!=&"":_consume_command(desired)

func _move_root(desired: Vector3, delta: float, acceleration: float=18.0) -> void:
 var feedback:=actor.physics_rig.get_root_feedback_velocity() if is_instance_valid(actor.physics_rig) else Vector3.ZERO
 desired+=feedback
 actor.velocity.x=move_toward(actor.velocity.x,desired.x,acceleration*delta)
 actor.velocity.z=move_toward(actor.velocity.z,desired.z,acceleration*delta)
 actor._gravity(delta)
 actor.move_and_slide()

func _restore_capsule() -> void:
 if _root_shape:
  _root_shape.height=_root_height
  if is_instance_valid(actor):actor.get_node("CollisionShape3D").position=_root_center

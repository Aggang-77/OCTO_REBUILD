class_name HunterCombatMoves
extends RefCounted
## Reach guides footwork and AI; damage still requires actual shape contact.
const MOVES={
 &"punch_jab":{"label":"잽","rate":1.75,"damage":10.0,"stamina":5.0,"step":0.12,"reach":0.75,"recovery":0.08,"impulse":1.8,"windows":[[0.34,0.57,&"left_hand"]]},
 &"punch_cross":{"label":"스트레이트","rate":2.25,"damage":15.0,"stamina":7.0,"step":0.24,"reach":0.95,"recovery":0.10,"impulse":2.8,"windows":[[0.87,1.13,&"right_hand"]]},
 &"punch_hook":{"label":"훅","rate":1.9,"damage":14.0,"stamina":7.0,"step":0.14,"reach":0.70,"recovery":0.10,"impulse":2.5,"windows":[[0.28,0.54,&"left_hand"]]},
 &"punch_quad":{"label":"펀치 4연타","rate":1.8,"damage":7.0,"stamina":18.0,"step":0.25,"reach":0.85,"recovery":0.10,"impulse":1.2,"windows":[[0.32,0.50,&"left_hand"],[0.55,0.73,&"right_hand"],[0.80,0.98,&"left_hand"],[1.05,1.29,&"right_hand"]]},
 &"kick_a":{"label":"오른발 하이킥","rate":1.9,"damage":23.0,"stamina":13.0,"step":0.48,"reach":1.50,"recovery":0.13,"impulse":4.0,"windows":[[0.52,1.20,&"right_foot"]]},
 &"kick_b":{"label":"왼발 킥","rate":1.9,"damage":19.0,"stamina":11.0,"step":0.40,"reach":1.25,"recovery":0.12,"impulse":3.5,"windows":[[0.38,0.95,&"left_foot"]]},
 &"kick_c":{"label":"오른발 미들킥","rate":1.95,"damage":20.0,"stamina":12.0,"step":0.44,"reach":1.35,"recovery":0.12,"impulse":3.6,"windows":[[0.36,0.90,&"right_foot"]]},
 &"kick_d":{"label":"회전 킥","rate":2.0,"damage":25.0,"stamina":16.0,"step":0.52,"reach":1.60,"recovery":0.15,"impulse":4.5,"windows":[[0.40,0.98,&"right_foot"]]},
 &"knee":{"label":"무릎 공격","rate":2.15,"damage":18.0,"stamina":9.0,"step":0.20,"reach":0.70,"recovery":0.10,"impulse":3.0,"windows":[[0.65,1.30,&"left_knee"]]},
 &"slide":{"label":"슬라이딩 태클","rate":1.45,"damage":14.0,"stamina":12.0,"step":0.0,"reach":2.0,"recovery":0.15,"impulse":3.4,"windows":[[0.22,0.95,&"right_foot",0],[0.22,0.95,&"left_foot",0],[0.22,0.95,&"left_shin",0],[0.22,0.95,&"right_shin",0]]},
 &"kick_front":{"label":"전진 킥","rate":2.0,"damage":21.0,"stamina":12.0,"step":0.58,"reach":1.65,"recovery":0.13,"impulse":3.8,"windows":[[0.92,1.42,&"right_foot"]]},
 &"kick_martelo":{"label":"마르텔루 킥","rate":2.0,"damage":24.0,"stamina":15.0,"step":0.52,"reach":1.65,"recovery":0.15,"impulse":4.2,"windows":[[0.60,1.25,&"left_foot"]]},
 &"elbow_strike":{"label":"엘보우","clip":"elbow","rate":2.8,"damage":17.0,"stamina":8.0,"step":0.10,"reach":0.58,"recovery":1.0,"cooldown":1.9,"impulse":3.0,"windows":[[0.18,0.82,&"right_elbow",0],[0.18,0.82,&"left_elbow",0]]},
 &"special_clinch":{"label":"얼굴 잡고 니킥","clip":"body_block","rate":2.15,"damage":32.0,"stamina":25.0,"step":0.12,"reach":0.65,"recovery":0.13,"impulse":4.2,"windows":[[0.13,0.55,&"left_hand",0],[0.13,0.55,&"right_hand",0],[1.84,2.12,&"left_knee",1]]},
 &"special_uppercut":{"label":"니킥 → 어퍼컷","clip":"combo_knee_upper","rate":2.5,"damage":16.0,"stamina":28.0,"step":0.40,"reach":0.95,"recovery":0.12,"impulse":3.2,"windows":[[0.74,1.02,&"right_hand"],[1.25,1.65,&"right_knee"],[2.05,2.50,&"right_knee"],[3.32,3.85,&"right_hand"]]},
 &"special_capoeira":{"label":"아르마다 → 지상 킥","rate":2.45,"damage":22.0,"window_damage":[18.0,26.0],"stamina":26.0,"step":0.45,"reach":1.5,"recovery":0.13,"full_recovery":true,"impulse":3.0,"windows":[[0.95,1.45,&"left_foot"],[2.63,3.20,&"right_foot"]]}}
const PUNCHES: Array[StringName]=[&"punch_jab",&"punch_cross",&"punch_hook"]
const KICKS: Array[StringName]=[&"kick_a",&"kick_b",&"kick_c",&"kick_d"]
const CHARACTER_KICKS=[[&"kick_front",&"kick_c",&"kick_b"],[&"kick_martelo",&"kick_a",&"kick_d"],[&"kick_b",&"kick_front",&"kick_a"],[&"kick_c",&"kick_d",&"kick_martelo"]]
const SPECIALS: Array[StringName]=[&"special_capoeira",&"special_clinch",&"special_uppercut",&"punch_quad"]
const PART_LABELS={&"head":"머리",&"torso":"몸통",&"pelvis":"골반",&"left_hand":"왼주먹",&"right_hand":"오른주먹",&"left_forearm":"왼팔",&"right_forearm":"오른팔",&"left_upper_arm":"왼상완",&"right_upper_arm":"오른상완",&"left_thigh":"왼허벅지",&"right_thigh":"오른허벅지",&"left_shin":"왼정강이",&"right_shin":"오른정강이",&"left_foot":"왼발",&"right_foot":"오른발",&"left_knee":"왼무릎",&"right_knee":"오른무릎",&"left_elbow":"왼팔꿈치",&"right_elbow":"오른팔꿈치"}

static func damage_multiplier(part: StringName) -> float:
 if part==&"head":return 1.4
 if part in [&"torso",&"pelvis"]:return 1.0
 return 0.65 if "arm" in part or "hand" in part else 0.75

static func physical_part(part: StringName) -> StringName:
 return StringName(String(part).replace("_knee","_shin").replace("_elbow","_forearm"))

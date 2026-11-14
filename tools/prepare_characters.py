"""Build the user supplied characters and retarget the supplied motion set."""
import bpy, os, sys, math, json
from mathutils import Matrix, Vector, Quaternion
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0,os.path.dirname(__file__))
from maya_ascii_mesh import load_maya_character
OUT=os.path.join(ROOT,'assets/characters');os.makedirs(OUT,exist_ok=True)
key=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else 'lily'
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene;scene.render.fps=30
if key=='lily':
    rig,meshes=load_maya_character(os.path.join(ROOT,'source_assets/character/All/Character.ma'))
elif key=='rin':
    bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT,'source_assets/rin/FBX with Atlas/Rin (Atlas FBX).fbx'))
    rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
    meshes=[o for o in bpy.data.objects if o.type=='MESH' and len(o.vertex_groups)]
elif key=='lily_orange':
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT,'source_assets/lily_orange/Lily_Orange_Restyle/Godot_Viewer/Lily_Orange_Restyle.glb'))
    rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
    meshes=[o for o in bpy.data.objects if o.type=='MESH' and len(o.vertex_groups)]
else:
    bpy.ops.import_scene.gltf(filepath=os.path.join(ROOT,'source_assets/aki/Aki SchoolGirl.glb'))
    rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
    meshes=[o for o in bpy.data.objects if o.type=='MESH' and len(o.vertex_groups)]

aliases={
 'Hips':['Hips','J_Bip_C_Hips','Root_M'],
 'Spine':['Spine','J_Bip_C_Spine','Spine1_M'],
 'Spine1':['J_Bip_C_Chest','Spine2_M'],
 'Spine2':['Chest','J_Bip_C_UpperChest','Chest_M'],
 'Neck':['Neck','J_Bip_C_Neck','Neck_M'],
 'Head':['Head','J_Bip_C_Head','Head_M']}
for side,word in [('R','Right'),('L','Left')]:
    for semantic,rin,vrm,maya in [('Shoulder','shoulder','Shoulder','Scapula'),('Arm','arm','UpperArm','Shoulder'),
       ('ForeArm','elbow','LowerArm','Elbow'),('Hand','wrist','Hand','Wrist'),('UpLeg','leg','UpperLeg','Hip'),
       ('Leg','knee','LowerLeg','Knee'),('Foot','ankle','Foot','Ankle'),('ToeBase','toe','ToeBase','Toes')]:
        aliases[word+semantic]=[word+' '+rin,'J_Bip_'+side+'_'+vrm,maya+'_'+side]
    for digit,rin,vrm,maya in [('Thumb','Thumb','Thumb','ThumbFinger'),('Index','IndexFinger','Index','IndexFinger'),
       ('Middle','MiddleFinger','Middle','MiddleFinger'),('Ring','RingFinger','Ring','RingFinger'),('Pinky','LittleFinger','Little','PinkyFinger')]:
        for i in range(1,4):
            aliases[word+'Hand'+digit+str(i)]=[rin+str(i-1 if digit=='Thumb' else i)+'_'+side,
                'J_Bip_'+side+'_'+vrm+str(i),maya+str(i)+'_'+side]
renames={}
for canonical,options in aliases.items():
    name=next((n for n in options if n in rig.data.bones),None)
    if name:renames[name]=canonical
for obj in meshes:
    for group in obj.vertex_groups:
        if group.name in renames:group.name=renames[group.name]
for old,new in renames.items():rig.data.bones[old].name=new
required=['Hips','Spine','Spine2','Neck','Head','RightArm','RightForeArm','RightHand','LeftArm','LeftForeArm','LeftHand','RightUpLeg','RightLeg','RightFoot','LeftUpLeg','LeftLeg','LeftFoot']
missing=[n for n in required if n not in rig.data.bones]
print('CHARACTER_BONES',key,list(rig.data.bones.keys()),flush=True)
if missing:raise RuntimeError('Missing body bones: '+str(missing))

# Normalize rest geometry into meters, facing Blender -Y / Godot +Z.
rig.animation_data_clear();rig.data.pose_position='REST'
bpy.context.view_layer.update()
rig_world=rig.matrix_world.copy()
mesh_world={o:o.matrix_world.copy() for o in meshes}
points=[mesh_world[o]@v.co for o in meshes for v in o.data.vertices]
minimum=min(p.z for p in points);maximum=max(p.z for p in points)
scale=1.65/(maximum-minimum)
foot=rig.data.bones['RightFoot']
toe=rig.data.bones.get('RightToeBase')
forward=rig_world.to_3x3()@((toe.head_local-foot.head_local) if toe else (foot.tail_local-foot.head_local))
angle=-math.pi/2-math.atan2(forward.y,forward.x)
normal=Matrix.Scale(scale,4)@Matrix.Rotation(angle,4,'Z')@Matrix.Translation(Vector((0,0,-minimum)))
for obj in meshes:
    obj.parent=None
    obj.data.transform(normal@mesh_world[obj]);obj.matrix_world=Matrix.Identity(4)
rig.parent=None;rig.matrix_world=Matrix.Identity(4);rig.data.transform(normal@rig_world)
rig.name='CharacterRig';rig.data.pose_position='POSE'
for pb in rig.pose.bones:
    for c in list(pb.constraints):pb.constraints.remove(c)
    pb.matrix_basis=Matrix.Identity(4)
for obj in meshes:
    obj.parent=rig;obj.matrix_world=Matrix.Identity(4)
    obj.hide_set(False);obj.hide_viewport=False;obj.hide_render=False
    for mod in list(obj.modifiers):
        if mod.type!='ARMATURE':obj.modifiers.remove(mod)
        else:mod.object=rig
    if not any(m.type=='ARMATURE' for m in obj.modifiers):obj.modifiers.new('Skin','ARMATURE').object=rig
for obj in list(bpy.data.objects):
    if obj not in meshes and obj!=rig:bpy.data.objects.remove(obj,do_unlink=True)
for mat in bpy.data.materials:
    if not mat.node_tree:continue
    for node in mat.node_tree.nodes:
        if node.type=='BSDF_PRINCIPLED':
            node.inputs['Roughness'].default_value=0.95
            node.inputs['Metallic'].default_value=0
            node.inputs['Specular IOR Level'].default_value=0.12
        if node.type=='TEX_IMAGE' and node.image and max(node.image.size)>4096:
            factor=4096/max(node.image.size);node.image.scale(int(node.image.size[0]*factor),int(node.image.size[1]*factor))

motions={'idle':('Idle',1,121),'jog':('Jogging',1,31),'sprint':('Sprint',1,23),'look':('Look Around',1,121),
 'elbow':('Illegal Elbow Punch',1,55),'slash':('Stable Sword Inward Slash',1,52),'combo':('One Hand Sword Combo',1,100),
 'stop':('Run To Stop',1,45),'turn_run':('Turn To Running',1,49),'fall':('Falling Down',1,70),'get_up':('Getting Up',1,100)}
combat_files={'punch_jab':'Punching','punch_cross':'Cross Punch','punch_hook':'Hook','punch_quad':'Quad Punch',
 'kick_a':'Mma Kick','kick_b':'Mma Kick (1)','kick_c':'Mma Kick (2)','kick_d':'Mma Kick (3)',
 'knee':'Knee Kick Lead','slide':'Running Slide','hit_head_a':'Big Hit To Head','hit_head_b':'Big Hit To Head (1)',
 'hit_head_c':'Big Hit To Head (2)','hit_body_a':'Hit To Body','hit_body_b':'Hit To Body (1)','down_pose':'Female Laying Pose'}
for clip,filename in combat_files.items():
    path=os.path.join(ROOT,'source_assets/motions_2/Girl_motion_2',filename+'.fbx')
    if os.path.exists(path):motions[clip]=(path,1,10000)
extra_files={'parry':'Outward Block','body_block':'Body Block','dodge':'Dodging','pivot':'Pivot',
 'evade_flip':'Backflip','kick_martelo':'Martelo 3','kick_front':'Kicking','combo_knee_upper':'Knee Jabs To Uppercut',
 'boxing_a':'Boxing (1)','boxing_b':'Boxing (2)','stunned':'Stunned',
 'celebrate':'Rumba Dancing','victory_pose':'Female Dance Pose'}
for clip,filename in extra_files.items():
    path=os.path.join(ROOT,'source_assets/motions_3/Girl_motion_3',filename+'.fbx')
    if os.path.exists(path):motions[clip]=(path,1,10000)
if key in ('lily','lily_orange'):
    for clip,filename in {'armada':'Armada','martelo_ground':'Martelo Do Chau'}.items():
        motions[clip]=(os.path.join(ROOT,'source_assets/motions_4/Girl_motion_4',filename+'.fbx'),1,10000)

# Split only hair faces from shared atlases, retaining the original texture/UVs.
for obj in meshes:
    old_materials=list(obj.data.materials)
    hair_groups={g.index for g in obj.vertex_groups if g.name=='Head' or g.name.startswith('HairJoint_') or g.name.startswith('J_Sec_Hair')}
    duplicates={}
    for polygon in obj.data.polygons:
        if polygon.material_index>=len(old_materials):continue
        mat=old_materials[polygon.material_index]
        if not mat:continue
        images=[n.image.name.lower() for n in mat.node_tree.nodes if n.type=='TEX_IMAGE' and n.image] if mat.node_tree else []
        hair=('hair' in mat.name.lower() or any('hearuv' in image for image in images))
        if key=='rin' and 'atlas' in mat.name.lower():
            weight=sum(sum(g.weight for g in obj.data.vertices[v].groups if g.group in hair_groups) for v in polygon.vertices)/len(polygon.vertices)
            hair=weight>0.45
        if hair:
            if mat.name not in duplicates:
                copy=mat.copy();copy.name='HunterHair_'+mat.name
                duplicates[mat.name]=len(obj.data.materials);obj.data.materials.append(copy)
            polygon.material_index=duplicates[mat.name]
    print('HAIR_SURFACES',obj.name,len(duplicates),flush=True)

from skirt_rig import build_skirt
build_skirt(rig,meshes,key)
from hair_rig import build_hair
build_hair(rig,meshes,key,OUT)

base=set(bpy.data.objects);actions=[];manifest={}
for clip,(file,start,end) in motions.items():
    bpy.ops.import_scene.fbx(filepath=file if os.path.isabs(file) else os.path.join(ROOT,'source_assets/motions/Gril_motion',file+'.fbx'))
    imported=set(bpy.data.objects)-base;source=next(o for o in imported if o.type=='ARMATURE')
    end=min(end,int(source.animation_data.action.frame_range[1]))
    source_world=source.matrix_world.copy()
    src_bones={b.name.split(':')[-1]:b for b in source.data.bones}
    src_pose={b.name.split(':')[-1]:b for b in source.pose.bones}
    refs={}
    def anatomical_direction(bones,semantic,world=Matrix.Identity(4)):
        children={'Hips':'Spine','Spine':'Spine1' if 'Spine1' in bones else 'Spine2','Spine1':'Spine2','Spine2':'Neck','Neck':'Head'}
        for word in ['Left','Right']:
            for first,last in [('Shoulder','Arm'),('Arm','ForeArm'),('ForeArm','Hand'),('Hand','HandMiddle1'),('UpLeg','Leg'),('Leg','Foot'),('Foot','ToeBase')]:
                children[word+first]=word+last
            for digit in ['Thumb','Index','Middle','Ring','Pinky']:
                children[word+'Hand'+digit+'1']=word+'Hand'+digit+'2'
                children[word+'Hand'+digit+'2']=word+'Hand'+digit+'3'
        child=children.get(semantic)
        if child and child in bones:direction=bones[child].head_local-bones[semantic].head_local
        elif semantic=='Head':direction=bones['Head'].head_local-bones['Neck'].head_local
        elif semantic.endswith('ToeBase'):direction=bones[semantic].head_local-bones[semantic.replace('ToeBase','Foot')].head_local
        elif semantic[-1:]=='3' and semantic[:-1]+'2' in bones:direction=bones[semantic].head_local-bones[semantic[:-1]+'2'].head_local
        else:direction=bones[semantic].tail_local-bones[semantic].head_local
        return (world.to_3x3()@direction).normalized()
    for target in aliases:
        if target not in rig.data.bones or target not in src_bones:continue
        tb=rig.data.bones[target];sb=src_bones[target]
        matrix=source_world@sb.matrix_local
        direction=anatomical_direction(src_bones,target,source_world)
        align=anatomical_direction(rig.data.bones,target).rotation_difference(direction)
        refs[target]=(matrix.to_quaternion().inverted(),align@tb.matrix_local.to_quaternion())
    rig.animation_data_create();rig.animation_data.action=None
    for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    action=bpy.data.actions.new(clip);rig.animation_data.action=action
    hips_rest=(source_world@src_bones['Hips'].matrix_local).translation
    height_scale=rig.data.bones['Hips'].head_local.z/hips_rest.z
    bpy.context.scene.frame_set(start)
    root_first=(source_world@src_pose['Hips'].matrix).to_quaternion()
    source_forward=anatomical_direction(src_bones,'RightFoot',source_world)
    root_reference=(source_world@src_bones['Hips'].matrix_local).to_quaternion()
    def yaw_of(rotation):
        forward=rotation@root_reference.inverted()@source_forward
        return math.atan2(forward.y,forward.x)
    initial_yaw=yaw_of(root_reference)
    for frame in range(start,end+1):
        scene.frame_set(frame);desired={}
        remove_yaw=Quaternion()
        if clip in ('turn_run','pivot','dodge'):
            yaw=yaw_of((source_world@src_pose['Hips'].matrix).to_quaternion())-initial_yaw
            remove_yaw=Quaternion((0,0,1),-yaw)
        for pb in rig.pose.bones:
            parent_rest=pb.parent.bone.matrix_local.to_quaternion() if pb.parent else Quaternion()
            parent_rotation=desired.get(pb.parent.name,parent_rest) if pb.parent else Quaternion()
            rest=pb.bone.matrix_local.to_quaternion()
            if pb.name in refs:
                inv,ref=refs[pb.name]
                rotation=remove_yaw@(source_world@src_pose[pb.name].matrix).to_quaternion()@inv@ref
                desired[pb.name]=rotation
                local=parent_rest.inverted()@rest
                pb.rotation_mode='QUATERNION';pb.rotation_quaternion=local.inverted()@parent_rotation.inverted()@rotation
                pb.keyframe_insert('rotation_quaternion',frame=frame-start)
                if pb.name=='Hips':
                    hips=(source_world@src_pose['Hips'].matrix).translation
                    pb.location=pb.bone.matrix_local.to_3x3().inverted()@Vector((0,0,(hips.z-hips_rest.z)*height_scale))
                    pb.keyframe_insert('location',frame=frame-start)
            else:desired[pb.name]=parent_rotation@parent_rest.inverted()@rest
    action.use_fake_user=True;actions.append(action)
    manifest[clip]={'seconds':(end-start)/30,'mapped_bones':len(refs)}
    for obj in imported:bpy.data.objects.remove(obj,do_unlink=True)
    print('BAKED',key,clip,flush=True)

# Join the user's two supplied attacks with a short pose crossfade. Every limb
# keeps its authored rotation; gameplay still tests the actual final foot path.
if all(any(a.name==name for a in actions) for name in ('armada','martelo_ground')):
    clips={a.name:a for a in actions}
    samples=[]
    for name in ('armada','martelo_ground'):
        rig.animation_data.action=clips[name]
        poses=[]
        for frame in range(int(clips[name].frame_range[1])+1):
            scene.frame_set(frame)
            poses.append({p.name:(p.rotation_quaternion.copy(),p.location.copy()) for p in rig.pose.bones})
        samples.append(poses)
    bridge=6
    sequence=list(samples[0])
    for frame in range(1,bridge+1):
        t=frame/bridge;t=t*t*(3-2*t)
        sequence.append({name:(samples[0][-1][name][0].slerp(samples[1][0][name][0],t),
            samples[0][-1][name][1].lerp(samples[1][0][name][1],t)) for name in samples[0][-1]})
    second_start=len(sequence)-1
    sequence.extend(samples[1][1:])
    action=bpy.data.actions.new('special_capoeira');rig.animation_data.action=action
    for frame,pose in enumerate(sequence):
        for pb in rig.pose.bones:
            if pb.name not in aliases:continue
            pb.rotation_mode='QUATERNION';pb.rotation_quaternion=pose[pb.name][0];pb.location=pose[pb.name][1]
            pb.keyframe_insert('rotation_quaternion',frame=frame)
            if pb.name=='Hips':pb.keyframe_insert('location',frame=frame)
    action.use_fake_user=True;actions.append(action)
    manifest['special_capoeira']={'seconds':(len(sequence)-1)/30,'mapped_bones':len(aliases),'followup_start':second_start/30}

# A guard stance sampled from the new jab, with a restrained breathing cycle.
if any(a.name=='punch_jab' for a in actions):
    rig.animation_data.action=next(a for a in actions if a.name=='punch_jab');scene.frame_set(0)
    guard={b.name:(b.rotation_quaternion.copy(),b.location.copy()) for b in rig.pose.bones}
    action=bpy.data.actions.new('combat_idle');rig.animation_data.action=action
    for frame in range(61):
        for pb in rig.pose.bones:
            pb.rotation_mode='QUATERNION';pb.rotation_quaternion=guard[pb.name][0];pb.location=guard[pb.name][1]
            if pb.name=='Spine2':pb.rotation_quaternion @= Quaternion((1,0,0),math.sin(frame/60*math.tau)*0.012)
            if pb.name in aliases:
                pb.keyframe_insert('rotation_quaternion',frame=frame)
                if pb.name=='Hips':pb.keyframe_insert('location',frame=frame)
    action.use_fake_user=True;actions.append(action)
    manifest['combat_idle']={'seconds':2.0,'mapped_bones':len(aliases)}

# Restrained posture: breathing, shoulders braced, slight forward torso lean.
rig.animation_data.action=next(a for a in actions if a.name=='idle');scene.frame_set(15)
pose={b.name:(b.rotation_quaternion.copy(),b.location.copy()) for b in rig.pose.bones}
action=bpy.data.actions.new('captured');rig.animation_data.action=action
for frame in range(61):
    for pb in rig.pose.bones:
        pb.rotation_mode='QUATERNION';pb.rotation_quaternion=pose[pb.name][0];pb.location=pose[pb.name][1]
        if pb.name=='Spine2':pb.rotation_quaternion @= Quaternion((1,0,0),0.18+math.sin(frame/60*math.tau)*0.025)
        if pb.name=='Head':pb.rotation_quaternion @= Quaternion((0,0,1),math.sin(frame/60*math.tau)*0.08)
        if pb.name in refs:
            pb.keyframe_insert('rotation_quaternion',frame=frame)
            if pb.name=='Hips':pb.keyframe_insert('location',frame=frame)
action.use_fake_user=True;actions.append(action)
rig.animation_data.action=None
for track in list(rig.animation_data.nla_tracks):rig.animation_data.nla_tracks.remove(track)
for action in actions:
    track=rig.animation_data.nla_tracks.new();track.name=action.name
    strip=track.strips.new(action.name,0,action);strip.action_frame_start=0;strip.action_frame_end=max(1,action.frame_range[1]);track.mute=True
for obj in meshes:
    for custom_key in list(obj.keys()):
        if custom_key!='_RNA_UI':del obj[custom_key]
bpy.ops.object.select_all(action='DESELECT')
for o in meshes+[rig]:o.select_set(True)
bpy.context.view_layer.objects.active=rig;scene.frame_set(0)
output=os.path.join(OUT,key+'.glb')
bpy.ops.export_scene.gltf(filepath=output,export_format='GLB',use_selection=True,export_animations=True,
 export_animation_mode='NLA_TRACKS',export_force_sampling=True,export_def_bones=False,export_morph=key=='lily_orange',
 export_skins=True,export_materials='EXPORT',export_yup=True)
with open(output.replace('.glb','_motions.json'),'w',encoding='utf-8') as f:json.dump(manifest,f,indent=2)
print('CHARACTER_EXPORT_COMPLETE',output,flush=True)

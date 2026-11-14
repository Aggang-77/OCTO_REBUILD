"""Bake supplied Mixamo FBX motions onto a compact hunter rig; Blender 4.4+.
Run: blender --background --python tools/prepare_hunter.py
Original archives remain untouched in source_assets (ignored by Godot).
"""
import bpy, os, math, json
from mathutils import Matrix, Vector, Quaternion

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCE = os.path.join(ROOT, 'source_assets/female_hunter')
OUT = os.path.join(ROOT, 'assets/hunter/hunter.glb')
bpy.ops.wm.open_mainfile(filepath=os.path.join(SOURCE, 'Female hunter rigged.blend'))
scene = bpy.context.scene
scene.render.fps = 30
original_rig = bpy.data.objects['rig']
original_rig.data.pose_position = 'REST'
bpy.context.view_layer.update()

def bake_particle_hair():
    """Preserve groomed parent/child paths as tapered crossed mesh ribbons."""
    scalp = bpy.data.objects.get('Scalp')
    if not scalp: return
    material = bpy.data.materials.get('Hair mat')
    for index, mod in enumerate(list(scalp.modifiers)):
        if mod.type != 'PARTICLE_SYSTEM': continue
        bpy.ops.object.select_all(action='DESELECT')
        scalp.select_set(True)
        bpy.context.view_layer.objects.active = scalp
        scalp.particle_systems.active_index = index
        before = set(bpy.data.objects)
        bpy.ops.object.modifier_convert(modifier=mod.name)
        converted = [o for o in set(bpy.data.objects)-before if o.type == 'MESH']
        for obj in converted:
            neighbors = [[] for _ in obj.data.vertices]
            for edge in obj.data.edges:
                a,b=edge.vertices
                neighbors[a].append(b); neighbors[b].append(a)
            paths=[]; visited=set()
            for start in range(len(neighbors)):
                if len(neighbors[start]) != 1 or start in visited: continue
                order=[]; current=start; previous=-1
                while current not in visited:
                    visited.add(current); order.append(current)
                    candidates=[n for n in neighbors[current] if n != previous]
                    if not candidates: break
                    previous,current=current,candidates[0]
                if len(order)>2: paths.append(order)
            vertices=[]; faces=[]
            step=max(1,math.ceil(len(paths)/1000))
            for order in paths[::step]:
                sampled=order[::max(1,len(order)//12)]
                if sampled[-1] != order[-1]: sampled.append(order[-1])
                points=[obj.matrix_world@obj.data.vertices[i].co for i in sampled]
                if (points[-1]-points[0]).length<0.005: continue
                start=len(vertices)
                for i,point in enumerate(points):
                    tangent=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
                    axis=tangent.cross(Vector((0,0,1)))
                    if axis.length<0.01: axis=tangent.cross(Vector((1,0,0)))
                    axis.normalize(); other=tangent.cross(axis).normalized()
                    width=0.0017*(1.0-i/max(1,len(points)-1))**0.55+0.00012
                    vertices.extend([point+axis*width,point-axis*width,point+other*width,point-other*width])
                    if i:
                        a=start+(i-1)*4; b=start+i*4
                        faces.extend([(a,a+1,b+1,b),(a+2,a+3,b+3,b+2)])
            mesh=bpy.data.meshes.new('GroomedHairMesh_%d'%index)
            mesh.from_pydata(vertices,[],faces); mesh.update()
            hair=bpy.data.objects.new('HairRibbons_%d'%index,mesh)
            scene.collection.objects.link(hair)
            hair.data.materials.append(material)
            # Remember the rigid bone binding until the compact rig exists.
            hair['bind_head']=True
            for polygon in mesh.polygons: polygon.use_smooth=True
            print('HAIR_MESH',index,'strands',len(paths[::step]),'vertices',len(vertices),flush=True)
            bpy.data.objects.remove(obj,do_unlink=True)
    for mod in list(scalp.modifiers):
        if mod.type=='PARTICLE_SYSTEM': scalp.modifiers.remove(mod)

bake_particle_hair()

def simplify_hair_surface():
    """Union the groom into a calm surface instead of thousands of visible strands."""
    parts=[o for o in bpy.data.objects if o.name.startswith('HairRibbons_') or o.name=='Scalp']
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts: o.select_set(True)
    bpy.context.view_layer.objects.active=next(o for o in parts if o.name.startswith('HairRibbons_'))
    bpy.ops.object.join()
    hair=bpy.context.object; hair.name='Hair_Smooth'; hair['bind_head']=True
    solid=hair.modifiers.new('Hair volume','SOLIDIFY'); solid.thickness=0.004
    bpy.ops.object.modifier_apply(modifier=solid.name)
    remesh=hair.modifiers.new('Merge fine strands','REMESH')
    remesh.mode='VOXEL'; remesh.voxel_size=0.007
    remesh.use_smooth_shade=True
    bpy.ops.object.modifier_apply(modifier=remesh.name)
    smooth=hair.modifiers.new('Soften groom','SMOOTH'); smooth.factor=1.1; smooth.iterations=8
    bpy.ops.object.modifier_apply(modifier=smooth.name)
    decimate=hair.modifiers.new('Game hair surface','DECIMATE'); decimate.ratio=0.55
    bpy.ops.object.modifier_apply(modifier=decimate.name)
    for polygon in hair.data.polygons: polygon.use_smooth=True
    print('SMOOTH_HAIR_VERTICES',len(hair.data.vertices),flush=True)

simplify_hair_surface()
meta = bpy.data.objects['metarig']
rig = meta.copy()
rig.data = meta.data.copy()
rig.name = 'HunterRig'
scene.collection.objects.link(rig)
rig.hide_set(False)
rig.hide_viewport = False
rig.animation_data_clear()
for pb in rig.pose.bones:
    for c in list(pb.constraints): pb.constraints.remove(c)
    pb.matrix_basis = Matrix.Identity(4)

# Keep real model geometry, exclude Rigify widgets, metarig and studio objects.
meshes = [o for o in list(bpy.data.objects) if o.type == 'MESH' and not o.name.startswith('WGT-')]
for obj in meshes:
    binding = obj.parent_bone.removeprefix('DEF-') if obj.parent_type == 'BONE' else ''
    if binding not in rig.data.bones and binding.endswith('.001'): binding=binding[:-4]
    if obj.name=='Scalp' or obj.get('bind_head'): binding='spine.006'
    world = obj.matrix_world.copy()
    obj.parent = rig
    obj.parent_type = 'OBJECT'
    obj.matrix_world = world
    obj.hide_set(False)
    obj.hide_viewport = False
    # Merge Rigify segmented deform groups into the matching metarig bone.
    weights = {}
    for v in obj.data.vertices:
        for entry in v.groups:
            name = obj.vertex_groups[entry.group].name
            name = name[4:] if name.startswith('DEF-') else name
            if name not in rig.data.bones and name.endswith('.001'):
                name = name[:-4]
            if name in rig.data.bones:
                weights.setdefault(name, {}).setdefault(v.index, 0.0)
                weights[name][v.index] += entry.weight
    obj.vertex_groups.clear()
    for name, entries in weights.items():
        group = obj.vertex_groups.new(name=name)
        for index, weight in entries.items(): group.add([index], min(weight, 1.0), 'REPLACE')
    for mod in list(obj.modifiers):
        if mod.type == 'ARMATURE': obj.modifiers.remove(mod)
        elif mod.type == 'SUBSURF': obj.modifiers.remove(mod)
    if weights:
        mod = obj.modifiers.new('Hunter skin', 'ARMATURE')
        mod.object = rig
    elif binding in rig.data.bones or 'Eyeball' in obj.name:
        group = obj.vertex_groups.new(name=binding if binding in rig.data.bones else 'spine.006')
        group.add(list(range(len(obj.data.vertices))), 1.0, 'REPLACE')
        obj.modifiers.new('Head skin', 'ARMATURE').object = rig

# Replace old shader graphs with glTF-compatible Principled materials.
def material_setup(mat):
    key = mat.name.lower()
    color = None
    normal = None
    base = (0.17, 0.10, 0.055, 1)
    metallic, rough = 0.0, 0.62
    if 'skin' in key:
        color, normal = 'skin2048_makeup.png', 'normal4096.png'
        base = (0.6, 0.37, 0.26, 1)
    elif 'outfit main' in key:
        color, normal = 'outfitColour2048.png', 'outfitNormal2048.png'
    elif key == 'material':
        color, normal = 'swordColour1024.png', 'swordNormal1024.png'
        metallic, rough = 0.8, 0.3
    elif 'dagger' in key:
        color, normal = 'daggerColour1024.png', 'daggerNormal1024.png'
        metallic, rough = 0.7, 0.3
    elif 'metal' in key: base, metallic, rough = (0.12,0.16,0.18,1), 0.8, 0.3
    elif 'hair' in key: base, rough = (0.68,0.49,0.22,1), 0.9
    elif 'teeth' in key: base = (0.8,0.76,0.66,1)
    elif 'eyeball' in key or 'cornea' in key: base = (0.85,0.87,0.83,1)
    elif 'iris' in key: base = (0.12,0.26,0.19,1)
    elif 'pupil' in key: base = (0.004,0.004,0.004,1)
    elif 'gum' in key: base = (0.25,0.04,0.04,1)
    mat.use_nodes = True
    mat.node_tree.nodes.clear()
    nodes, links = mat.node_tree.nodes, mat.node_tree.links
    shader = nodes.new('ShaderNodeBsdfPrincipled')
    shader.inputs['Base Color'].default_value = base
    shader.inputs['Roughness'].default_value = rough
    shader.inputs['Metallic'].default_value = metallic
    if 'hair' in key: shader.inputs['Specular IOR Level'].default_value = 0.18
    output = nodes.new('ShaderNodeOutputMaterial')
    links.new(shader.outputs['BSDF'], output.inputs['Surface'])
    for filename, is_normal in [(color,False),(normal,True)]:
        if not filename: continue
        image = bpy.data.images.load(os.path.join(SOURCE,'Textures',filename), check_existing=False)
        # 2K is enough for this 1.7m gameplay character.
        if max(image.size) > 2048: image.scale(2048,2048)
        tex = nodes.new('ShaderNodeTexImage'); tex.image = image
        if is_normal:
            image.colorspace_settings.name = 'Non-Color'
            norm = nodes.new('ShaderNodeNormalMap')
            links.new(tex.outputs['Color'],norm.inputs['Color'])
            links.new(norm.outputs['Normal'],shader.inputs['Normal'])
        else: links.new(tex.outputs['Color'],shader.inputs['Base Color'])
for mat in bpy.data.materials: material_setup(mat)

# The original groom now forms one smooth blonde surface bound to the head.

# Put the supplied right sword into the right hand in the rest pose.
sword = bpy.data.objects.get('Sword Right')
if sword:
    coords = [v.co.copy() for v in sword.data.vertices]
    lower = Vector(tuple(min(v[i] for v in coords) for i in range(3)))
    upper = Vector(tuple(max(v[i] for v in coords) for i in range(3)))
    long_axis = max(range(3), key=lambda i: upper[i]-lower[i])
    direction = Vector(tuple(1.0 if i == long_axis else 0.0 for i in range(3)))
    hand = rig.data.bones['hand.R']
    # Blade points outward along the hand local +Y axis.
    turn = direction.rotation_difference(Vector((0,-1,0)))
    center = (lower+upper)*0.5
    for v in sword.data.vertices:
        local = turn @ (v.co-center)
        v.co = hand.matrix_local @ (local + Vector((0,-0.20,0)))
    sword.matrix_world = rig.matrix_world.copy()
    sword.vertex_groups.clear()
    sword.vertex_groups.new(name='hand.R').add(list(range(len(sword.data.vertices))),1.0,'REPLACE')
    for mod in list(sword.modifiers):
        if mod.type=='ARMATURE': sword.modifiers.remove(mod)
    sword.modifiers.new('Weapon grip','ARMATURE').object=rig
    sword.name='Sword_Hand'
for obj in list(bpy.data.objects):
    if obj not in meshes and obj != rig:
        bpy.data.objects.remove(obj,do_unlink=True)
for obj in list(meshes):
    if obj.name in ['Sword Left','Dagger']:
        meshes.remove(obj); bpy.data.objects.remove(obj,do_unlink=True)

mapping = {'spine':'Hips','spine.001':'Spine','spine.002':'Spine1','spine.003':'Spine2',
           'spine.004':'Neck','spine.005':'Neck','spine.006':'Head'}
for side, word in [('L','Left'),('R','Right')]:
    for target, source in [('shoulder','Shoulder'),('upper_arm','Arm'),('forearm','ForeArm'),('hand','Hand'),
                           ('thigh','UpLeg'),('shin','Leg'),('foot','Foot'),('toe','ToeBase')]:
        mapping[f'{target}.{side}'] = word+source
    for digit, source in [('thumb','Thumb'),('f_index','Index'),('f_middle','Middle'),('f_ring','Ring'),('f_pinky','Pinky')]:
        for i in range(1,4): mapping[f'{digit}.{i:02d}.{side}'] = word+'Hand'+source+str(i)

motions = {'idle':('Idle',1,121),'jog':('Jogging',1,31),'sprint':('Sprint',1,23),
           'look':('Look Around',1,121),'elbow':('Illegal Elbow Punch',1,55),
           'slash':('Stable Sword Inward Slash',1,52),'combo':('One Hand Sword Combo',1,100),
           'stop':('Run To Stop',1,45),'turn_run':('Turn To Running',1,49),
           'fall':('Falling Down',1,70),'get_up':('Getting Up',1,100)}
actions=[]; manifest={}
base_objects=set(bpy.data.objects)
for clip,(filename,start,end) in motions.items():
    bpy.ops.import_scene.fbx(filepath=os.path.join(ROOT,'source_assets/motions/Gril_motion',filename+'.fbx'))
    imported=set(bpy.data.objects)-base_objects
    source=next(o for o in imported if o.type=='ARMATURE')
    source_action=source.animation_data.action
    end=min(end,int(source_action.frame_range[1]))
    src_bones={b.name.split(':')[-1]:b for b in source.data.bones}
    src_pose={b.name.split(':')[-1]:b for b in source.pose.bones}
    source_world=source.matrix_world.copy()
    refs={}
    for target,src in mapping.items():
        if target not in rig.data.bones or src not in src_bones: continue
        tb=rig.data.bones[target]; sb=src_bones[src]
        sm=source_world@sb.matrix_local
        src_direction=(source_world.to_3x3()@(sb.tail_local-sb.head_local)).normalized()
        target_direction=(tb.tail_local-tb.head_local).normalized()
        align=target_direction.rotation_difference(src_direction)
        refs[target]=(src,sm.to_quaternion().inverted(),align@tb.matrix_local.to_quaternion())
    rig.animation_data_create()
    rig.animation_data.action=None
    for pb in rig.pose.bones: pb.matrix_basis=Matrix.Identity(4)
    action=bpy.data.actions.new(clip)
    rig.animation_data.action=action
    scene.frame_set(start)
    hips_rest=(source_world@src_bones['Hips'].matrix_local).translation
    height_scale=rig.data.bones['spine'].head_local.z / hips_rest.z
    for frame in range(start,end+1):
        scene.frame_set(frame)
        desired={}
        for pb in rig.pose.bones:
            if pb.name in refs:
                src,inv,ref=refs[pb.name]
                rotation=(source_world@src_pose[src].matrix).to_quaternion()@inv@ref
                desired[pb.name]=rotation
                parent_rotation=desired.get(pb.parent.name,pb.parent.bone.matrix_local.to_quaternion()) if pb.parent else Quaternion()
                rest_rotation=pb.bone.matrix_local.to_quaternion()
                parent_rest=pb.parent.bone.matrix_local.to_quaternion() if pb.parent else Quaternion()
                rest_local=parent_rest.inverted()@rest_rotation
                pb.rotation_mode='QUATERNION'
                pb.rotation_quaternion=rest_local.inverted()@parent_rotation.inverted()@rotation
                pb.keyframe_insert('rotation_quaternion',frame=frame-start)
                if pb.name=='spine':
                    hips=(source_world@src_pose['Hips'].matrix).translation
                    # In-place clips: physics owns X/Z movement, retain vertical bounce.
                    delta=Vector((0,0,(hips.z-hips_rest.z)*height_scale))
                    pb.location=pb.bone.matrix_local.to_3x3().inverted()@delta
                    pb.keyframe_insert('location',frame=frame-start)
            else:
                parent_rotation=desired.get(pb.parent.name,pb.parent.bone.matrix_local.to_quaternion()) if pb.parent else Quaternion()
                parent_rest=pb.parent.bone.matrix_local.to_quaternion() if pb.parent else Quaternion()
                desired[pb.name]=parent_rotation@parent_rest.inverted()@pb.bone.matrix_local.to_quaternion()
    action.use_fake_user=True
    actions.append(action)
    manifest[clip]={'source':filename+'.fbx','frames':end-start+1,'seconds':(end-start)/30.0,'mapped_bones':len(refs)}
    for obj in imported: bpy.data.objects.remove(obj,do_unlink=True)
    print('BAKED',clip,manifest[clip],flush=True)

# Restrained idle uses a compact defensive pose, with a breathing cycle.
rig.animation_data.action=next(a for a in actions if a.name=='idle')
scene.frame_set(15)
pose={b.name:(b.rotation_quaternion.copy(),b.location.copy()) for b in rig.pose.bones}
action=bpy.data.actions.new('captured'); rig.animation_data.action=action
for frame in range(0,61):
    for pb in rig.pose.bones:
        pb.rotation_mode='QUATERNION'
        pb.rotation_quaternion=pose[pb.name][0]
        pb.location=pose[pb.name][1]
        if pb.name=='spine.002': pb.rotation_quaternion @= Quaternion((1,0,0),0.17+math.sin(frame/60*math.tau)*0.025)
        if pb.name=='spine.006': pb.rotation_quaternion @= Quaternion((0,0,1),math.sin(frame/60*math.tau)*0.08)
        if pb.name in refs or pb.name in mapping:
            pb.keyframe_insert('rotation_quaternion',frame=frame)
            if pb.name=='spine': pb.keyframe_insert('location',frame=frame)
action.use_fake_user=True; actions.append(action)
manifest['captured']={'source':'Idle.fbx + defensive breathing pose','seconds':2.0}

# NLA tracks provide stable action names in the GLB.
rig.animation_data.action=None
for track in list(rig.animation_data.nla_tracks): rig.animation_data.nla_tracks.remove(track)
for action in actions:
    track=rig.animation_data.nla_tracks.new(); track.name=action.name
    strip=track.strips.new(action.name,0,action); strip.action_frame_start=0
    strip.action_frame_end=max(1,action.frame_range[1]); track.mute=True
bpy.ops.object.select_all(action='DESELECT')
for obj in [rig]+meshes: obj.select_set(True)
bpy.context.view_layer.objects.active=rig
scene.frame_set(0)
bpy.ops.export_scene.gltf(filepath=OUT,export_format='GLB',use_selection=True,
    export_animations=True,export_animation_mode='NLA_TRACKS',export_nla_strips_merged_animation_name='idle',
    export_force_sampling=True,export_def_bones=False,export_skins=True,export_morph=False,
    export_materials='EXPORT',export_image_format='AUTO',export_yup=True,export_apply=False)
with open(os.path.join(ROOT,'assets/hunter/motion_manifest.json'),'w',encoding='utf-8') as f: json.dump(manifest,f,indent=2)
print('HUNTER_EXPORT_COMPLETE',OUT,flush=True)

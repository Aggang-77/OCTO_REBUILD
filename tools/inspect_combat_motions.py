import bpy, os, json, math, sys
from mathutils import Vector
ROOT=os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
batch=sys.argv[sys.argv.index('--')+1] if '--' in sys.argv else '2'
folder=os.path.join(ROOT,'source_assets/motions_'+batch,'Girl_motion_'+batch)
report={}
for filename in sorted(os.listdir(folder)):
    if not filename.lower().endswith('.fbx'):continue
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.fbx(filepath=os.path.join(folder,filename))
    rig=next(o for o in bpy.data.objects if o.type=='ARMATURE')
    action=rig.animation_data.action
    start,end=map(int,action.frame_range)
    bones={b.name.split(':')[-1]:b for b in rig.pose.bones}
    tracks={name:[] for name in ('LeftHand','RightHand','LeftFoot','RightFoot','LeftLeg','RightLeg','Hips','Head')}
    for frame in range(start,end+1):
        bpy.context.scene.frame_set(frame)
        for name in tracks:
            tracks[name].append(list(rig.matrix_world@bones[name].matrix.translation))
    peaks={}
    for name,points in tracks.items():
        if name in ('Hips','Head'):continue
        velocity=[]
        for index in range(1,len(points)):
            a=Vector(points[index])-Vector(tracks['Hips'][index])
            b=Vector(points[index-1])-Vector(tracks['Hips'][index-1])
            velocity.append((a-b).length*30)
        candidates=sorted(range(len(velocity)),key=lambda i:velocity[i],reverse=True)
        chosen=[]
        for i in candidates:
            if all(abs(i-j)>5 for j in chosen):chosen.append(i)
            if len(chosen)==4:break
        peaks[name]=[{'time':round((i+1)/30,3),'speed':round(velocity[i],3),'position':points[i+1]} for i in sorted(chosen)]
    report[filename]={'frames':[start,end],'seconds':(end-start)/30,'fps':bpy.context.scene.render.fps,
        'peaks':peaks,'hips_start':tracks['Hips'][0],'hips_end':tracks['Hips'][-1],
        'hips_min':[min(v[i] for v in tracks['Hips']) for i in range(3)]}
    print('COMBAT_CLIP',filename,report[filename]['seconds'],flush=True)
with open(os.path.join(ROOT,'.tools/combat_motion_'+batch+'_inspection.json'),'w') as f:json.dump(report,f,indent=2)

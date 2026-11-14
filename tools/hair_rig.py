"""Split only tagged hair into soft front/side/back chains; scalp stays on Head."""
import bpy, math, json, os
from mathutils import Vector

def build_hair(rig, meshes, key, out):
    head=rig.data.bones['Head'].head_local.copy()
    selected={}
    for obj in meshes:
        ids={v for p in obj.data.polygons if obj.data.materials[p.material_index] and obj.data.materials[p.material_index].name.startswith('HunterHair_') for v in p.vertices}
        if ids:selected[obj]=ids
    points=[obj.data.vertices[i].co.copy() for obj,ids in selected.items() for i in ids]
    root_z=min(head.z+0.15,max(p.z for p in points)-0.045)
    def sector(p):return ((math.atan2(p.y-head.y,p.x-head.x)%math.tau)/math.tau)*8
    entries=[]
    bpy.context.view_layer.objects.active=rig
    bpy.ops.object.mode_set(mode='EDIT')
    for panel in range(8):
        angle=(panel+0.5)*math.tau/8
        candidates=[p for p in points if abs(((sector(p)-(panel+0.5)+4)%8)-4)<1.15 and p.z<root_z]
        bottom=max(head.z-0.95,min((p.z for p in candidates),default=head.z-0.05))
        bottom=min(bottom,root_z-0.10)
        chain=[]
        for index in range(4):
            z=root_z+(bottom-root_z)*index/3
            near=[p for p in candidates if abs(p.z-z)<(root_z-bottom)*0.24]
            radius=sum(math.hypot(p.x-head.x,p.y-head.y) for p in near)/len(near) if near else 0.10
            chain.append(Vector((head.x+math.cos(angle)*radius,head.y+math.sin(angle)*radius,z)))
        parent=rig.data.edit_bones['Head']
        front=math.sin(angle)<-0.45
        for index in range(3):
            name=f'HairFlow_{panel:02}_{index}'
            bone=rig.data.edit_bones.new(name)
            bone.head=chain[index];bone.tail=chain[index+1];bone.parent=parent;bone.use_connect=index>0
            parent=bone
            tail=chain[index+1]
            entries.append({'bone':name,'end':[tail.x,tail.z,-tail.y],
                'max_angle':math.radians((5+index*3) if front else (10+index*6)),
                'front':front,'length':bone.length})
    bpy.ops.object.mode_set(mode='OBJECT')
    for obj,ids in selected.items():
        head_group=obj.vertex_groups.get('Head') or obj.vertex_groups.new(name='Head')
        groups={(p,i):obj.vertex_groups.new(name=f'HairFlow_{p:02}_{i}') for p in range(8) for i in range(3)}
        for vi in ids:
            vertex=obj.data.vertices[vi];p=vertex.co
            if p.z>=root_z:continue
            for assignment in list(vertex.groups):obj.vertex_groups[assignment.group].remove([vi])
            # Adjacent sectors blend without splitting the mesh or texture.
            angle=(sector(p)-0.5)%8;panel=int(angle);mix=angle-panel
            remaining=1.0
            for section,angular_weight in ((panel,1-mix),((panel+1)%8,mix)):
                bones=[rig.data.bones[f'HairFlow_{section:02}_{i}'] for i in range(3)]
                depth=max(0,min(2.999,(root_z-p.z)/(root_z-bones[-1].tail_local.z)*3))
                segment=int(depth);fraction=depth-segment
                if segment==0:
                    value=fraction*angular_weight
                    if value>0:groups[section,0].add([vi],value,'REPLACE');remaining-=value
                else:
                    for index,weight in ((segment-1,1-fraction),(segment,fraction)):
                        value=weight*angular_weight
                        if value>0:groups[section,index].add([vi],value,'REPLACE');remaining-=value
            if remaining>0.00001:head_group.add([vi],remaining,'REPLACE')
    with open(os.path.join(out,key+'_secondary.json'),'w') as f:json.dump({'hair':entries},f,indent=2)
    print('HAIR_FLOW_RIG',key,'vertices',len(points),'chains',8,'segments',3,flush=True)
